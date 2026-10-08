import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/data/gap/gap_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/pack_fixture.dart';

const userId = '0192f5a0-0000-7000-8000-000000000001';
const courseId = '0192f5a0-0000-7000-8000-0000000000c1';

void main() {
  late AppDatabase db;
  late DateTime now;
  late DriftGapRepository gaps;
  var next = 0;

  setUp(() {
    db = memoryDatabase();
    now = DateTime.utc(2026, 10, 8, 9);
    next = 0;
    gaps = DriftGapRepository(db, now: () => now, newId: () => 'id-${next++}');
  });
  tearDown(() => db.close());

  Future<List<(String, String, String)>> outbox() async => [
    for (final e in await db.select(db.outbox).get())
      (e.targetTable, e.rowId, e.op),
  ];

  Future<GapEntry> capture([String text = '  canım sıkıldı  ']) => gaps.capture(
    userId: userId,
    courseId: courseId,
    l1Text: text,
    context: GapContext.pair,
    note: '   ',
  );

  test('a capture is stored and queued; its suggestion waits', () async {
    final entry = await capture();
    expect(entry.id, 'id-0');
    expect(entry.l1Text, 'canım sıkıldı');
    expect(entry.context, GapContext.pair);
    expect(entry.status, GapStatus.fresh);
    expect(entry.note, isNull);
    expect(entry.suggestion, isNull);
    expect(entry.createdAt, now);
    final row = await db.select(db.gapEntries).getSingle();
    expect(row.context, 'pair');
    expect(row.status, 'new');
    expect(row.pendingPush, isTrue);
    expect(await outbox(), [('gap_entries', 'id-0', 'upsert')]);
  });

  test('the suggestion is kept as the route gave it', () async {
    final entry = await capture();
    now = now.add(const Duration(minutes: 1));
    await gaps.saveSuggestion(entry.id, gapSuggestion());

    final saved = (await gaps.entry(entry.id))!;
    expect(saved.suggestion, gapSuggestion());
    final row = await db.select(db.gapEntries).getSingle();
    expect(row.suggestion!['l2_natural'], "Let's go out, I'm bored.");
    expect(row.suggestion!['key_chunk'], {
      'text': 'go out',
      'gloss_l1': 'dışarı çıkmak',
    });
    expect(row.updatedAt, now);
    expect(await outbox(), hasLength(2));
  });

  test('a suggestion that no longer reads is no suggestion', () async {
    final entry = await capture();
    await db
        .update(db.gapEntries)
        .write(const GapEntriesCompanion(suggestion: Value({'l2_natural': 1})));
    expect((await gaps.entry(entry.id))!.suggestion, isNull);
  });

  test(
    'added to the cards: the sentence and the phrase become items',
    () async {
      final entry = await capture();
      await gaps.addToCards(
        userId: userId,
        courseId: courseId,
        id: entry.id,
        sentence: 'I am bored. We can go out.',
        variants: ["Let's go out, I'm bored.", 'I am bored. We can go out.'],
        sentenceLemmas: const ['i', 'be', 'bored', 'we', 'can', 'go', 'out'],
        chunk: const KeyChunk(text: 'go out', glossL1: 'dışarı çıkmak'),
        chunkLemmas: const ['go', 'out'],
        notes: "'bored' sıkılmış demektir.",
      );

      final items = await db.select(db.personalItems).get();
      expect(items, hasLength(2));
      final [sentence, chunk] = items;
      expect(sentence.kind, 'sentence');
      expect(sentence.textL2, 'I am bored. We can go out.');
      expect(sentence.glossL1, 'canım sıkıldı');
      // The sentence itself is not its own variant.
      expect(sentence.variants, ["Let's go out, I'm bored."]);
      expect(sentence.source, 'gap');
      expect(sentence.lemmas, ['i', 'be', 'bored', 'we', 'can', 'go', 'out']);
      expect(chunk.lemmas, ['go', 'out']);
      expect(sentence.notes, "'bored' sıkılmış demektir.");
      expect(chunk.kind, 'chunk');
      expect(chunk.textL2, 'go out');
      expect(chunk.glossL1, 'dışarı çıkmak');

      final carded = (await gaps.entry(entry.id))!;
      expect(carded.status, GapStatus.carded);
      expect(carded.personalItemIds, [sentence.id, chunk.id]);
      expect(await outbox(), [
        ('gap_entries', entry.id, 'upsert'),
        ('personal_items', sentence.id, 'upsert'),
        ('personal_items', chunk.id, 'upsert'),
        ('gap_entries', entry.id, 'upsert'),
      ]);
    },
  );

  test('without the phrase only the sentence becomes an item', () async {
    final entry = await capture();
    await gaps.addToCards(
      userId: userId,
      courseId: courseId,
      id: entry.id,
      sentence: 'Never mind.',
    );
    expect(await db.select(db.personalItems).get(), hasLength(1));
    expect(
      () => gaps.addToCards(
        userId: userId,
        courseId: courseId,
        id: 'none',
        sentence: 'x',
      ),
      throwsArgumentError,
    );
  });

  test('dismissed, and listed newest first', () async {
    final first = await capture('bir');
    now = now.add(const Duration(minutes: 1));
    final second = await capture('iki');
    await gaps.dismiss(first.id);
    final listed = await gaps.watchEntries(courseId).first;
    expect(listed.map((e) => e.id), [second.id, first.id]);
    expect(listed.last.status, GapStatus.dismissed);
    expect(await gaps.watchEntries('other').first, isEmpty);
  });
}
