import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/placement_bank.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';

void main() {
  late AppDatabase db;
  late PlacementBankRepository repository;

  setUp(() {
    db = memoryDatabase();
    repository = PlacementBankRepository(db.contentDao);
  });

  tearDown(() => db.close());

  Future<void> import(BuiltPack pack) async {
    final result = await PackImporter(db).import(pack.bytes, pack.info);
    expect(result, isA<Ok<void, Object>>());
  }

  group('PlacementBankRepository (docs/06-assessment.md §2)', () {
    test('without content there is no test', () async {
      expect(await repository.load(l2: 'zz', taken: 0), isNull);
      expect(await repository.watchAvailable('zz').first, isFalse);
    });

    test('a pack from before the placement test holds none', () async {
      await import(await placementPack(withVocabLevels: false));

      expect(await repository.load(l2: 'zz', taken: 0), isNull);
      expect(await repository.watchAvailable('zz').first, isFalse);
    });

    test('reads the first version of the word list and dictation', () async {
      await import(await placementPack());

      final bank = (await repository.load(l2: 'zz', taken: 0))!;

      expect(bank.version, 'A');
      expect(bank.words, [
        (key: 'zz.xlex.A.fake', word: 'fakea', band: null),
        for (var band = 1; band <= 5; band++)
          (key: 'zz.xlex.A.w$band', word: 'w${band}a', band: band),
      ]);
      expect(bank.vocabLevels.estimate(450), LevelEstimate.at(CefrLevel.a2));
      // The clip at normal speed, from the pack's audio prefix; sentences
      // in the order they are played.
      expect(bank.dictation, [
        (
          key: 'zz.pdict.a.1',
          level: CefrLevel.a1,
          text: 'Bada kolu.',
          clip: 'zz/1/v1/one.mp3',
        ),
        (
          key: 'zz.pdict.a.2',
          level: CefrLevel.a2,
          text: 'Kolu bada kolu.',
          clip: 'zz/1/v1/two.mp3',
        ),
      ]);
    });

    test('holds the whole grammar bank by level', () async {
      await import(await placementPack());

      final bank = (await repository.load(l2: 'zz', taken: 0))!;

      expect(bank.grammar.keys, [CefrLevel.a1, CefrLevel.a2]);
      final (:key, :level, :stem, :answer, :distractors) =
          bank.grammar[CefrLevel.a2]!.single;
      expect(
        (key, level, stem, answer),
        ('zz.pgram.a2.one', CefrLevel.a2, 'Bada ___ kolu.', 'miA2'),
      );
      expect(distractors, ['mo', 'mu']);
    });

    test('the versions take turns from one test to the next', () async {
      await import(await placementPack());

      final second = (await repository.load(l2: 'zz', taken: 1))!;
      final third = (await repository.load(l2: 'zz', taken: 2))!;

      expect(second.version, 'B');
      expect(second.words.map((w) => w.word), contains('w1b'));
      expect(second.dictation.single.key, 'zz.pdict.b.1');
      expect(third.version, 'A');
    });

    test('scores writing with the pack words and normalization', () async {
      await import(await placementPack());

      final bank = (await repository.load(l2: 'zz', taken: 0))!;

      expect(bank.language.tokenize('Bada  Kolu.'), ['bada', 'kolu']);
      expect(bank.language.knows('kolu'), isTrue);
      expect(bank.language.knows('kolv'), isFalse);
    });

    test('follows the content as packs arrive', () async {
      final seen = repository.watchAvailable('zz');
      final values = <bool>[];
      final subscription = seen.listen(values.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await import(await placementPack());
      await pumpEventQueue();

      expect(values, [false, true]);
    });
  });
}
