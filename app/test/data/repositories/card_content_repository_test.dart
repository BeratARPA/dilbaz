import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/card_content_repository.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pack_fixture.dart';

const pack = 'zz@1';

Future<void> install(AppDatabase db) async {
  final target = await buildPack(
    id: pack,
    kind: 'target',
    manifest: {
      'min_engine_version': 1,
      'script': {'direction': 'ltr', 'word_separator': 'space'},
    },
    meta: {
      'audio': {'prefix': 'zz/'},
    },
    normalization: soundNormalization,
    items: [
      item(
        'zz.ws.bada.n.1',
        'word_sense',
        packId: pack,
        text: 'bada',
        lemmas: ['bada'],
        rank: 12,
        data: {
          'carriers': ['zz.sent.0002', 'zz.sent.0001'],
        },
      ),
      item('zz.ws.kolu.v.1', 'word_sense', packId: pack, text: 'kolu'),
      item(
        'zz.sent.0001',
        'sentence',
        packId: pack,
        text: 'Bada kolu.',
        lemmas: ['bada', 'kolu'],
        targets: ['zz.ws.bada.n.1', 'zz.ws.kolu.v.1'],
        data: {
          'audio': [
            {'voice': 'v1', 'speed': 1.0, 'file': 'v1/a.mp3'},
            {'voice': 'v1', 'speed': 0.8, 'file': 'v1/b.mp3'},
          ],
        },
      ),
      item(
        'zz.sent.0002',
        'sentence',
        packId: pack,
        text: 'Bada sima dero.',
        lemmas: ['bada', 'sima', 'dero'],
        targets: ['zz.ws.bada.n.1'],
      ),
      item('zz.chunk.kolu_bada', 'chunk', packId: pack, text: 'Kolu bada.'),
    ],
    links: [
      ContentLinksCompanion.insert(
        fromKey: 'zz.ws.bada.n.1',
        toKey: 'zz.ws.kolu.v.1',
        type: 'contrasts_with',
        packId: pack,
      ),
    ],
    forms: [
      ContentFormsCompanion.insert(form: 'bada', lemma: 'bada', packId: pack),
      ContentFormsCompanion.insert(form: 'kolu', lemma: 'kolu', packId: pack),
    ],
  );
  final pair = await buildPack(
    id: 'qq-zz@1',
    kind: 'pair',
    l1: 'qq',
    pairEntries: [
      for (final (key, data) in [
        ('zz.ws.bada.n.1', {'meaning': 'anlam', 'usage_note': 'nasıl'}),
        ('zz.sent.0001', {'meaning': 'Bada kolu diye sor.', 'context': 'dost'}),
        ('zz.sent.0002', {'meaning': 'Başka bir cümle.'}),
        ('zz.chunk.kolu_bada', {'meaning': 'Kalıp.'}),
      ])
        ContentPairEntriesCompanion.insert(
          kind: 'gloss',
          key: key,
          packId: 'qq-zz@1',
          data: data,
        ),
      ContentPairEntriesCompanion.insert(
        kind: 'variants',
        key: 'zz.sent.0001',
        packId: 'qq-zz@1',
        data: const {
          'variants': ['Kolu bada.'],
          'alternatives': ['Sima kolu.'],
          'grammar': {
            'Kolu bada.': ['gp.zz.one'],
          },
        },
      ),
      ContentPairEntriesCompanion.insert(
        kind: 'contrast_note',
        key: 'zz.ws.bada.n.1|zz.ws.kolu.v.1',
        packId: 'qq-zz@1',
        data: const {
          'items': ['zz.ws.bada.n.1', 'zz.ws.kolu.v.1'],
          'note': 'bada ≠ kolu',
        },
      ),
    ],
  );
  for (final built in [target, pair]) {
    final result = await PackImporter(db).import(built.bytes, built.info);
    expect(result, isA<Ok<void, PackFailure>>(), reason: built.info.id);
  }
}

void main() {
  personalTests();
  late AppDatabase db;
  late DriftCardContentRepository content;

  setUp(() async {
    db = memoryDatabase();
    await install(db);
    content = DriftCardContentRepository(db, l2: 'zz');
  });
  tearDown(() => db.close());

  const knowsKolu = LemmaKnowledge(known: {'kolu'}, ranks: {});

  test(
    'a word card is asked with the carrier the learner knows best',
    () async {
      final card = (await content.content(
        'zz.ws.bada.n.1',
        knowledge: knowsKolu,
      ))!;

      // "Bada kolu." hides nothing else; "Bada sima dero." hides two words.
      expect(card.carrierKey, 'zz.sent.0001');
      expect(card.kind, ItemKind.wordSense);
      expect(card.prompt, 'Bada kolu diye sor.');
      expect(card.contextNote, 'dost');
      expect(
        card.answerKey,
        const AnswerKey(
          reference: 'Bada kolu.',
          targetLemmas: {'bada'},
          variants: ['Kolu bada.'],
          alternatives: ['Sima kolu.'],
          answerGrammar: {
            'Kolu bada.': ['gp.zz.one'],
          },
        ),
      );
      expect(card.targetSpan, 'bada');
      expect(card.clip, 'zz/v1/a.mp3');
      expect(card.slowClip, 'zz/v1/b.mp3');
      expect(card.headword, 'bada');
      expect(card.meaning, 'anlam');
      expect(card.usageNote, 'nasıl');
      expect(card.contrastNote, 'bada ≠ kolu');
    },
  );

  test('a chunk is its own carrier and its own target', () async {
    final card = (await content.content(
      'zz.chunk.kolu_bada',
      knowledge: knowsKolu,
    ))!;
    expect(card.carrierKey, 'zz.chunk.kolu_bada');
    expect(card.prompt, 'Kalıp.');
    expect(card.answerKey.targetLemmas, isEmpty);
    expect(card.targetSpan, 'Kolu bada.');
    expect(card.clip, isNull);
  });

  test('items without a card of their own give none', () async {
    for (final key in ['zz.sent.0001', 'zz.ws.kolu.v.1', 'zz.nothing']) {
      expect(
        await content.content(key, knowledge: knowsKolu),
        isNull,
        reason: key,
      );
    }
  });

  test('items, links and the language come from the target pack', () async {
    final items = await content.items();
    expect(items.map((i) => i.key), contains('zz.ws.bada.n.1'));
    expect(items.firstWhere((i) => i.key == 'zz.sent.0001').targets, [
      'zz.ws.bada.n.1',
      'zz.ws.kolu.v.1',
    ]);
    expect(await content.links(), [
      const ItemLink(
        from: 'zz.ws.bada.n.1',
        to: 'zz.ws.kolu.v.1',
        type: LinkType.contrastsWith,
      ),
    ]);
    final language = (await content.language())!;
    expect(language.normalize('Bada kolu.'), 'bada kolu');
  });
}

void personalTests() {
  group('personal items (A19)', () {
    late AppDatabase db;
    late DriftCardContentRepository content;

    setUp(() async {
      db = memoryDatabase();
      await install(db);
      content = DriftCardContentRepository(db, l2: 'zz');
      await db.batch((batch) {
        batch.insertAll(db.personalItems, [
          PersonalItemsCompanion.insert(
            id: 'p1',
            profileId: 'u',
            courseId: 'c1',
            kind: 'sentence',
            textL2: 'Kolu bada sima.',
            source: 'gap',
            glossL1: const Value('kolu bada demek istedim'),
            variants: const Value(['Bada kolu sima.']),
            notes: const Value('not'),
          ),
          PersonalItemsCompanion.insert(
            id: 'p2',
            profileId: 'u',
            courseId: 'c1',
            kind: 'chunk',
            textL2: 'sima dero',
            source: 'gap',
            glossL1: const Value('sima dero'),
            cefr: const Value('B1'),
          ),
          // Without a meaning there is nothing to ask with.
          PersonalItemsCompanion.insert(
            id: 'p3',
            profileId: 'u',
            courseId: 'c1',
            kind: 'chunk',
            textL2: 'x',
            source: 'gap',
          ),
          PersonalItemsCompanion.insert(
            id: 'p4',
            profileId: 'u',
            courseId: 'other',
            kind: 'chunk',
            textL2: 'y',
            source: 'gap',
            glossL1: const Value('y'),
          ),
        ]);
      });
    });
    tearDown(() => db.close());

    test("are phrases to say, at their own level or the learner's", () async {
      final items = await content.personalItems('c1', CefrLevel.a2);
      expect(items.map((i) => (i.key, i.kind, i.level, i.text)), [
        ('personal:p1', ItemKind.chunk, CefrLevel.a2, 'Kolu bada sima.'),
        ('personal:p2', ItemKind.chunk, CefrLevel.b1, 'sima dero'),
      ]);
    });

    test("are asked with the learner's own words", () async {
      final card = (await content.content(
        'personal:p1',
        knowledge: const LemmaKnowledge(known: {}, ranks: {}),
      ))!;
      expect(card.prompt, 'kolu bada demek istedim');
      expect(card.carrierKey, 'personal:p1');
      expect(card.answerKey.reference, 'Kolu bada sima.');
      expect(card.answerKey.variants, ['Bada kolu sima.']);
      expect(card.answerKey.targetLemmas, isEmpty);
      expect(card.targetSpan, 'Kolu bada sima.');
      expect(card.headword, 'Kolu bada sima.');
      expect(card.meaning, 'kolu bada demek istedim');
      expect(card.usageNote, 'not');
      expect(card.clip, isNull);
      expect(
        await content.content(
          'personal:p3',
          knowledge: const LemmaKnowledge(known: {}, ranks: {}),
        ),
        isNull,
      );
    });
  });
}
