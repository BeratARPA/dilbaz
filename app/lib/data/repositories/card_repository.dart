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
  CardMode.type => 'card.produce_type',
  _ => 'card.produce_speak',
};

/// Cards and their attempts (docs/13-data-model.md §2.3). Attempts are
/// events: written once, never changed (I-03); a card's row can always be
/// rebuilt from its last rated attempt.
abstract interface class CardRepository {
  /// The course's active cards.
  Future<List<StoredCard>> cards(String courseId);

  /// The evidence of every item with a card, projected from the attempts
  /// (docs/04-learner-model.md §3, I-04).
  Future<Map<String, ItemEvidence>> evidence(String courseId);

  /// Latencies of the latest answers in [mode], newest first, for the Easy
  /// rating (docs/03 §0.3).
  Future<List<int>> recentLatencies(String courseId, CardMode mode);

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
  /// for the server.
  Future<void> recordReview({
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
  static bool _evidence(AttemptRow row) =>
      row.targetOk == true &&
      const {
        'correct',
        'acceptable_variant',
        'minor_error',
      }.contains(row.verdict);

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
  Future<Map<String, ItemEvidence>> evidence(String courseId) async {
    final cards = await this.cards(courseId);
    final rated =
        await (_db.select(_db.attempts)
              ..where((t) => t.courseId.equals(courseId) & t.rating.isNotNull())
              ..orderBy([(t) => OrderingTerm(expression: t.createdAtClient)]))
            .get();
    final reviews = <String, List<ReviewRecord>>{};
    for (final row in rated) {
      final after = row.cardStateAfter;
      final cardId = row.cardId;
      if (after == null || cardId == null) continue;
      (reviews[cardId] ??= []).add(
        ReviewRecord(
          at: row.createdAtClient,
          rating: ReviewRating.values.firstWhere((r) => r.code == row.rating),
          evidence: _evidence(row),
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
    for (final row in rows) {
      // Only the LLM's verdicts: a listed answer matches anyway.
      if (row.prompt['carrier'] != carrierKey || row.llm?['provider'] == null) {
        continue;
      }
      if (row.response['text'] case final String text) {
        (row.targetOk == true ? variants : alternatives).add(text);
      }
    }
    return (variants: [...variants], alternatives: [...alternatives]);
  }

  @override
  Future<void> recordReview({
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
    });
  }
}
