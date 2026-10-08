import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:drift/drift.dart';
import 'package:json_annotation/json_annotation.dart'
    show CheckedFromJsonException;
import 'package:uuid/uuid.dart';

/// "Söyleyemediklerim" (A19, docs/13-data-model.md §2.4): captures, their
/// suggestions, and the personal items a capture becomes. Every write goes
/// to the outbox in the same transaction.
abstract interface class GapRepository {
  /// The course's captures, newest first.
  Stream<List<GapEntry>> watchEntries(String courseId);

  /// One capture; null when there is none with [id].
  Future<GapEntry?> entry(String id);

  /// Stores what the learner could not say; its suggestion comes later.
  Future<GapEntry> capture({
    required String userId,
    required String courseId,
    required String l1Text,
    required GapContext context,
    String? note,
  });

  Future<void> saveSuggestion(String id, GapSuggestion suggestion);

  Future<void> dismiss(String id);

  /// Makes [sentence], with the other correct [variants], a personal item
  /// asked with the capture's own words, and [chunk] one asked with its
  /// meaning. They reach the cards through the curriculum, within the
  /// day's new items (I-07). The lemmas are those of the target pack's
  /// forms (docs/10 §7).
  Future<void> addToCards({
    required String userId,
    required String courseId,
    required String id,
    required String sentence,
    List<String> variants = const [],
    List<String> sentenceLemmas = const [],
    KeyChunk? chunk,
    List<String> chunkLemmas = const [],
    String? notes,
  });
}

String _uuidV7() => const Uuid().v7();

class DriftGapRepository implements GapRepository {
  new(this._db, {this._now = nowUtc, this._newId = _uuidV7});

  final AppDatabase _db;
  final DateTime Function() _now;
  final String Function() _newId;

  static const _gapEntries = 'gap_entries';
  static const _personalItems = 'personal_items';
  static const _upsert = 'upsert';
  static const _source = 'gap';

  static GapEntry _entry(GapEntryRow row) => GapEntry(
    id: row.id,
    l1Text: row.l1Text,
    context: GapContext.values.firstWhere(
      (c) => c.code == row.context,
      orElse: () => GapContext.daily,
    ),
    status: GapStatus.values.firstWhere(
      (s) => s.code == row.status,
      orElse: () => GapStatus.fresh,
    ),
    createdAt: row.createdAt,
    note: row.note,
    suggestion: _suggestion(row.suggestion),
    personalItemIds: row.personalItemIds,
  );

  /// A stored suggestion, or none when it no longer reads.
  static GapSuggestion? _suggestion(Map<String, Object?>? json) {
    if (json == null) return null;
    try {
      return GapSuggestion.fromJson(json);
    } on CheckedFromJsonException {
      return null;
    }
  }

  @override
  Stream<List<GapEntry>> watchEntries(String courseId) =>
      (_db.select(_db.gapEntries)
            ..where((t) => t.courseId.equals(courseId))
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.createdAt,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch()
          .map((rows) => [for (final row in rows) _entry(row)]);

  @override
  Future<GapEntry?> entry(String id) async {
    final row = await (_db.select(
      _db.gapEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _entry(row);
  }

  Future<void> _queue(String table, String rowId) => _db
      .into(_db.outbox)
      .insert(
        OutboxCompanion.insert(targetTable: table, rowId: rowId, op: _upsert),
      );

  @override
  Future<GapEntry> capture({
    required String userId,
    required String courseId,
    required String l1Text,
    required GapContext context,
    String? note,
  }) => _db.transaction(() async {
    final now = _now();
    final id = _newId();
    final trimmedNote = note?.trim();
    await _db
        .into(_db.gapEntries)
        .insert(
          GapEntriesCompanion.insert(
            id: id,
            profileId: userId,
            courseId: courseId,
            l1Text: l1Text.trim(),
            context: context.code,
            note: Value(
              trimmedNote == null || trimmedNote.isEmpty ? null : trimmedNote,
            ),
            updatedAt: Value(now),
            createdAt: Value(now),
            pendingPush: const Value(true),
          ),
        );
    await _queue(_gapEntries, id);
    return (await entry(id))!;
  });

  Future<void> _update(String id, GapEntriesCompanion change) =>
      _db.transaction(() async {
        await (_db.update(_db.gapEntries)..where((t) => t.id.equals(id))).write(
          change.copyWith(
            updatedAt: Value(_now()),
            pendingPush: const Value(true),
          ),
        );
        await _queue(_gapEntries, id);
      });

  @override
  Future<void> saveSuggestion(String id, GapSuggestion suggestion) =>
      _update(id, GapEntriesCompanion(suggestion: Value(suggestion.toJson())));

  @override
  Future<void> dismiss(String id) =>
      _update(id, GapEntriesCompanion(status: Value(GapStatus.dismissed.code)));

  @override
  Future<void> addToCards({
    required String userId,
    required String courseId,
    required String id,
    required String sentence,
    List<String> variants = const [],
    List<String> sentenceLemmas = const [],
    KeyChunk? chunk,
    List<String> chunkLemmas = const [],
    String? notes,
  }) => _db.transaction(() async {
    final gap = await entry(id);
    if (gap == null) throw ArgumentError.value(id, 'id', 'unknown_gap');
    final now = _now();
    PersonalItemsCompanion item({
      required String itemId,
      required String kind,
      required String text,
      required String gloss,
      required List<String> lemmas,
      List<String> variants = const [],
      String? notes,
    }) => PersonalItemsCompanion.insert(
      id: itemId,
      profileId: userId,
      courseId: courseId,
      kind: kind,
      textL2: text.trim(),
      source: _source,
      glossL1: Value(gloss.trim()),
      lemmas: Value(lemmas),
      notes: Value(notes),
      variants: Value([
        for (final variant in variants)
          if (variant.trim() != sentence.trim()) variant.trim(),
      ]),
      updatedAt: Value(now),
      createdAt: Value(now),
      pendingPush: const Value(true),
    );
    final sentenceId = _newId();
    final items = [
      item(
        itemId: sentenceId,
        kind: 'sentence',
        text: sentence,
        gloss: gap.l1Text,
        lemmas: sentenceLemmas,
        variants: variants,
        notes: notes,
      ),
      if (chunk != null)
        item(
          itemId: _newId(),
          kind: 'chunk',
          text: chunk.text,
          gloss: chunk.glossL1,
          lemmas: chunkLemmas,
        ),
    ];
    await _db.batch((batch) {
      batch.insertAll(_db.personalItems, items);
    });
    for (final item in items) {
      await _queue(_personalItems, item.id.value);
    }
    await (_db.update(_db.gapEntries)..where((t) => t.id.equals(id))).write(
      GapEntriesCompanion(
        status: Value(GapStatus.carded.code),
        personalItemIds: Value([for (final item in items) item.id.value]),
        updatedAt: Value(now),
        pendingPush: const Value(true),
      ),
    );
    await _queue(_gapEntries, id);
  });
}
