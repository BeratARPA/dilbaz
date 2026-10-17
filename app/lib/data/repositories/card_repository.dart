import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:dilbaz_app/data/repositories/attempt_draft.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// A card as a session works with it: learner × item × mode.
typedef StoredCard = ({
  String id,
  String itemRef,
  CardMode mode,
  CardMemory memory,

  /// When the item was introduced.
  DateTime createdAt,
});

/// The learner's own correct answers to one carrier: those the LLM
/// accepted as variants, with the card's target or without it
/// (docs/03 §0.5 step 3).
typedef PersonalAnswers = ({List<String> variants, List<String> alternatives});

/// The activity code of a card answer in [mode] (docs/03-activities.md).
String cardActivity(CardMode mode) => switch (mode) {
  CardMode.speak => 'card.produce_speak',
  CardMode.type => 'card.produce_type',
  CardMode.cloze => 'card.cloze',
  CardMode.contrast => 'card.contrast',
  CardMode.recognizeAudio => 'card.recognize_audio',
  CardMode.dictation => 'dictation',
};

/// Cards and their attempts (docs/13-data-model.md §2.3). Attempts are
/// events: written once, never changed (I-03); a card's row can always be
/// rebuilt from its last rated attempt.
abstract interface class CardRepository {
  /// The course's active cards.
  Future<List<StoredCard>> cards(String courseId);

  /// The evidence of every item with a card, projected from the attempts
  /// (docs/04-learner-model.md §3, I-04); of [itemRef] alone when given.
  Future<Map<String, ItemEvidence>> evidence(
    String courseId, {
    String? itemRef,
  });

  /// Latencies of the latest answers in [mode], newest first, for the Easy
  /// rating (docs/03 §0.3).
  Future<List<int>> recentLatencies(String courseId, CardMode mode);

  /// Share of first-try recalls (Good, Easy) among the reviews rated since
  /// [since]; null without any (docs/05 §3, line 12; P10).
  Future<double?> unaidedAccuracySince(String courseId, DateTime since);

  /// How many reviews were rated since [since].
  Future<int> reviewsSince(String courseId, DateTime since);

  /// The answers to [carrierKey] on the card of [itemRef] that the LLM
  /// accepted; they match without it next time. They are read from the
  /// attempts, which keep them anyway (I-03).
  Future<PersonalAnswers> personalAnswers({
    required String courseId,
    required String itemRef,
    required String carrierKey,
  });

  /// The card of a newly introduced item; the existing one if it has one.
  Future<StoredCard> introduce({
    required String userId,
    required String courseId,
    required String itemRef,
    required CardMode mode,
  });

  /// Stores a finished review in one transaction: its [attempts], chained
  /// and the last one rated, and the card's memory [after] it; both queued
  /// for the server. Returns the attempts' ids, in order.
  Future<List<String>> recordReview({
    required String userId,
    required String courseId,
    required String deviceId,
    required StoredCard card,
    required List<AttemptDraft> attempts,
    required ReviewRating rating,
    required CardMemory after,
  });
}

String _uuidV7() => const Uuid().v7();

class DriftCardRepository implements CardRepository {
  new(this._db, {this._now = nowUtc, this._newId = _uuidV7});

  final AppDatabase _db;
  final DateTime Function() _now;
  final String Function() _newId;
  final _scheduler = SrsScheduler();

  static const _cards = 'cards';
  static const _attempts = 'attempts';
  static const _insert = 'insert';
  static const _upsert = 'upsert';

  /// Verdicts that recall the target when it came through (docs/03 §0.2).
  static bool _recalls(String? verdict, Object? targetOk) =>
      targetOk == true &&
      const {'correct', 'acceptable_variant', 'minor_error'}.contains(verdict);

  /// An attempt's evidence: the tutor's late verdict when there is one
  /// (`llm_resolved`, docs/03 §0.3), else its own.
  static bool _evidence(AttemptRow row, Map<String, Object?>? late) =>
      switch (late) {
        {'verdict': final String verdict} => _recalls(
          verdict,
          late['target_ok'],
        ),
        _ => _recalls(row.verdict, row.targetOk),
      };

  static const _resolved = 'llm_resolved';

  /// The tutor's late verdicts on answers of [courseId] (and [itemRef]), by
  /// attempt, with the attempts.
  Future<List<({AttemptRow attempt, Map<String, Object?> verdict})>> _late(
    String courseId, {
    String? itemRef,
  }) async {
    final attempts = _db.attempts;
    final amendments = _db.attemptAmendments;
    final query =
        _db.select(amendments).join([
            innerJoin(attempts, attempts.id.equalsExp(amendments.attemptId)),
          ])
          ..where(
            attempts.courseId.equals(courseId) &
                amendments.kind.equals(_resolved) &
                (itemRef == null
                    ? const Constant(true)
                    : attempts.itemRef.equals(itemRef)),
          )
          ..orderBy([OrderingTerm(expression: amendments.createdAt)]);
    return [
      for (final row in await query.get())
        (
          attempt: row.readTable(attempts),
          verdict: row.readTable(amendments).payload,
        ),
    ];
  }

  static StoredCard _stored(CardRow row) => (
    id: row.id,
    itemRef: row.itemRef,
    mode: CardMode.values.firstWhere((m) => m.code == row.mode),
    memory: CardMemory(
      fsrsCardId: row.fsrsCardId,
      state: MemoryState.values.firstWhere((s) => s.code == row.state),
      due: row.due,
      step: row.step,
      stability: row.stability,
      difficulty: row.difficulty,
      lastReview: row.lastReview,
      reps: row.reps,
      lapses: row.lapses,
    ),
    createdAt: row.createdAt,
  );

  @override
  Future<List<StoredCard>> cards(String courseId) async {
    final rows =
        await (_db.select(_db.cards)..where(
              (t) => t.courseId.equals(courseId) & t.suspended.equals(false),
            ))
            .get();
    return [for (final row in rows) _stored(row)];
  }

  @override
  Future<Map<String, ItemEvidence>> evidence(
    String courseId, {
    String? itemRef,
  }) async {
    final cards = [
      for (final card in await this.cards(courseId))
        if (itemRef == null || card.itemRef == itemRef) card,
    ];
    final rated =
        await (_db.select(_db.attempts)
              ..where(
                (t) =>
                    t.courseId.equals(courseId) &
                    t.rating.isNotNull() &
                    (itemRef == null
                        ? const Constant(true)
                        : t.itemRef.equals(itemRef)),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.createdAtClient)]))
            .get();
    final late = {
      for (final (:attempt, :verdict) in await _late(courseId))
        attempt.id: verdict,
    };
    final ids = {for (final card in cards) card.id};
    final ofItem = <String, List<StoredCard>>{};
    for (final card in cards) {
      (ofItem[card.itemRef] ??= []).add(card);
    }
    final reviews = <String, List<ReviewRecord>>{};
    for (final row in rated) {
      final after = row.cardStateAfter;
      final cardId = row.cardId;
      if (after == null || cardId == null) continue;
      final card = ids.contains(cardId) ? cardId : _merged(row, ofItem);
      if (card == null) continue;
      (reviews[card] ??= []).add(
        ReviewRecord(
          at: row.createdAtClient,
          rating: ReviewRating.values.firstWhere((r) => r.code == row.rating),
          evidence: _evidence(row, late[row.id]),
          stability: CardMemory.fromJson(after).stability ?? 0,
        ),
      );
    }
    final byItem = <String, List<CardRecord>>{};
    for (final card in cards) {
      (byItem[card.itemRef] ??= []).add(
        CardRecord(
          mode: card.mode,
          memory: card.memory,
          reviews: reviews[card.id] ?? const [],
        ),
      );
    }
    return {
      for (final MapEntry(:key, :value) in byItem.entries)
        key: ItemEvidence(value),
    };
  }

  /// The card an attempt counts for when its own card is gone: a card this
  /// device made before the server's card of the same item and mode is
  /// merged into it on sync (docs/12 §6), and its attempts keep its id
  /// (I-03). The item's only card, else its card in the answer's mode.
  static String? _merged(AttemptRow row, Map<String, List<StoredCard>> ofItem) {
    final cards = ofItem[row.itemRef] ?? const <StoredCard>[];
    if (cards.length == 1) return cards.single.id;
    for (final card in cards) {
      if (cardActivity(card.mode) == row.activity) return card.id;
    }
    return null;
  }

  @override
  Future<List<int>> recentLatencies(String courseId, CardMode mode) async {
    final rows =
        await (_db.select(_db.attempts)
              ..where(
                (t) =>
                    t.courseId.equals(courseId) &
                    t.activity.equals(cardActivity(mode)) &
                    t.latencyMs.isNotNull(),
              )
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAtClient,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(LatencyProfile.window))
            .get();
    return [for (final row in rows) row.latencyMs!];
  }

  CardsCompanion _memory(CardMemory memory, DateTime now) => CardsCompanion(
    state: Value(memory.state.code),
    step: Value(memory.step),
    stability: Value(memory.stability),
    difficulty: Value(memory.difficulty),
    due: Value(memory.due),
    lastReview: Value(memory.lastReview),
    reps: Value(memory.reps),
    lapses: Value(memory.lapses),
    updatedAt: Value(now),
    pendingPush: const Value(true),
  );

  @override
  Future<StoredCard> introduce({
    required String userId,
    required String courseId,
    required String itemRef,
    required CardMode mode,
  }) => _db.transaction(() async {
    final existing =
        await (_db.select(_db.cards)..where(
              (t) =>
                  t.profileId.equals(userId) &
                  t.itemRef.equals(itemRef) &
                  t.mode.equals(mode.code),
            ))
            .getSingleOrNull();
    if (existing != null) return _stored(existing);
    final now = _now();
    final memory = _scheduler.newCard(
      fsrsCardId: now.microsecondsSinceEpoch,
      now: now,
    );
    final id = _newId();
    await _db
        .into(_db.cards)
        .insert(
          _memory(memory, now).copyWith(
            id: Value(id),
            profileId: Value(userId),
            courseId: Value(courseId),
            itemRef: Value(itemRef),
            mode: Value(mode.code),
            fsrsCardId: Value(memory.fsrsCardId),
            createdAt: Value(now),
          ),
        );
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(targetTable: _cards, rowId: id, op: _upsert),
        );
    return (
      id: id,
      itemRef: itemRef,
      mode: mode,
      memory: memory,
      createdAt: now,
    );
  });

  static const _acceptableVariant = 'acceptable_variant';

  Future<List<int>> _ratingsSince(String courseId, DateTime since) async {
    final rows =
        await (_db.select(_db.attempts)..where(
              (t) =>
                  t.courseId.equals(courseId) &
                  t.rating.isNotNull() &
                  t.createdAtClient.isBiggerOrEqualValue(since),
            ))
            .get();
    return [for (final row in rows) row.rating!];
  }

  @override
  Future<double?> unaidedAccuracySince(String courseId, DateTime since) async {
    final ratings = await _ratingsSince(courseId, since);
    if (ratings.isEmpty) return null;
    final unaided = ratings.where(
      (r) => r == ReviewRating.good.code || r == ReviewRating.easy.code,
    );
    return unaided.length / ratings.length;
  }

  @override
  Future<int> reviewsSince(String courseId, DateTime since) async =>
      (await _ratingsSince(courseId, since)).length;

  @override
  Future<PersonalAnswers> personalAnswers({
    required String courseId,
    required String itemRef,
    required String carrierKey,
  }) async {
    final rows =
        await (_db.select(_db.attempts)
              ..where(
                (t) =>
                    t.courseId.equals(courseId) &
                    t.itemRef.equals(itemRef) &
                    t.verdict.equals(_acceptableVariant),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.createdAtClient)]))
            .get();
    final variants = <String>{};
    final alternatives = <String>{};
    void add(AttemptRow row, Object? targetOk) {
      if (row.prompt['carrier'] != carrierKey) return;
      if (row.response['text'] case final String text) {
        (targetOk == true ? variants : alternatives).add(text);
      }
    }

    for (final row in rows) {
      // Only the LLM's verdicts: a listed answer matches anyway.
      if (row.llm?['provider'] != null) add(row, row.targetOk);
    }
    // Answers the tutor accepted later: checked without it, or disputed.
    for (final (:attempt, :verdict) in await _late(
      courseId,
      itemRef: itemRef,
    )) {
      if (verdict['verdict'] == _acceptableVariant) {
        add(attempt, verdict['target_ok']);
      }
    }
    return (variants: [...variants], alternatives: [...alternatives]);
  }

  @override
  Future<List<String>> recordReview({
    required String userId,
    required String courseId,
    required String deviceId,
    required StoredCard card,
    required List<AttemptDraft> attempts,
    required ReviewRating rating,
    required CardMemory after,
  }) {
    if (attempts.isEmpty) throw ArgumentError.value(attempts, 'attempts');
    return _db.transaction(() async {
      final now = _now();
      final ids = [for (final _ in attempts) _newId()];
      await _db.batch((batch) {
        for (final (i, draft) in attempts.indexed) {
          final last = i == attempts.length - 1;
          batch.insert(
            _db.attempts,
            AttemptsCompanion.insert(
              id: ids[i],
              profileId: userId,
              courseId: courseId,
              deviceId: deviceId,
              activity: draft.activity,
              itemRef: Value(card.itemRef),
              cardId: Value(card.id),
              parentAttemptId: Value(i == 0 ? null : ids[i - 1]),
              prompt: draft.prompt,
              response: draft.response,
              verdict: Value(draft.verdict),
              targetOk: Value(draft.targetOk),
              errorTags: Value(draft.errorTags),
              hintsUsed: Value(draft.hintsUsed),
              hintMaxLevel: Value(draft.hintMaxLevel),
              rating: Value(last ? rating.code : null),
              latencyMs: Value(draft.latencyMs),
              durationMs: Value(draft.durationMs),
              cardStateAfter: Value(last ? after.toJson() : null),
              llm: Value(draft.llm),
              createdAtClient: draft.createdAtClient,
              createdAt: Value(now),
              pendingPush: const Value(true),
            ),
          );
        }
        batch
          ..update(
            _db.cards,
            _memory(after, now),
            where: (t) => t.id.equals(card.id),
          )
          ..insertAll(_db.outbox, [
            for (final id in ids)
              OutboxCompanion.insert(
                targetTable: _attempts,
                rowId: id,
                op: _insert,
              ),
            OutboxCompanion.insert(
              targetTable: _cards,
              rowId: card.id,
              op: _upsert,
            ),
          ]);
      });
      return ids;
    });
  }
}
