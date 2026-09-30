import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pack_fixture.dart';

void main() {
  late AppDatabase db;
  late PackImporter importer;

  setUp(() {
    db = memoryDatabase();
    importer = PackImporter(db);
  });

  tearDown(() => db.close());

  Future<List<String>> keys() async => [
    for (final row in await db.contentDao.itemsOfKinds([
      'word_sense',
      'chunk',
      'sentence',
      'lemma',
    ]))
      row.key,
  ];

  Future<PackFailure?> failureOf(BuiltPack pack) async =>
      switch (await importer.import(pack.bytes, pack.info)) {
        Ok() => null,
        Err(:final error) => error,
      };

  group('PackImporter (docs/11-language-packs.md §5)', () {
    test('copies the rows of a pack and records it', () async {
      final pack = await targetPack();

      expect(await failureOf(pack), isNull);

      expect(await keys(), [
        'zz.chunk.bada_kolu',
        'zz.lemma.bada',
        'zz.sent.0001',
        'zz.ws.bada.n.1',
        'zz.ws.kolu.v.1',
      ]);
      final sentence = (await db.contentDao.item('zz.sent.0001'))!;
      expect(sentence.textL2, 'Bada kolu.');
      expect(sentence.lemmas, ['bada', 'kolu']);
      expect(sentence.targets, ['zz.ws.bada.n.1', 'zz.ws.kolu.v.1']);
      expect((await db.contentDao.forms())['badaven'], {'bada'});
      final recorded = (await db.contentDao.packs()).single;
      expect(recorded.packId, 'zz@1');
      expect(recorded.kind, 'target');
      expect(recorded.checksum, pack.info.checksum);
      expect(recorded.importedAt.isUtc, isTrue);
      // The whole pack_meta is kept: manifest, normalization and the rest.
      expect(
        recorded.manifest.keys,
        containsAll(['manifest', 'normalization']),
      );
    });

    test('a new version replaces the old one, a pair pack stays', () async {
      expect(await failureOf(await targetPack()), isNull);
      expect(await failureOf(await pairPack()), isNull);

      final next = await targetPack(id: 'zz@2', version: 2, word: 'mire');
      expect(await failureOf(next), isNull);

      expect(await keys(), isNot(contains('zz.ws.bada.n.1')));
      expect(await keys(), contains('zz.ws.mire.n.1'));
      expect((await db.contentDao.forms()).keys, isNot(contains('bada')));
      expect(
        [for (final pack in await db.contentDao.packs()) pack.packId],
        ['qq-zz@1', 'zz@2'],
      );
      expect(await db.contentDao.pairEntry('gloss', 'zz.ws.bada.n.1'), {
        'meaning': 'anlam',
      });
      expect(await db.contentDao.linksOfType('contrasts_with'), hasLength(1));
    });

    test('importing the same pack again changes nothing', () async {
      final pack = await targetPack();
      expect(await failureOf(pack), isNull);
      final before = await keys();
      expect(await failureOf(pack), isNull);
      expect(await keys(), before);
      expect(await db.contentDao.packs(), hasLength(1));
    });

    test('refuses a file format it does not know', () async {
      expect(
        await failureOf(await targetPack(formatVersion: 2)),
        PackFailure.unsupported,
      );
      expect(await keys(), isEmpty);
    });

    test('refuses a pack that needs a newer engine', () async {
      final pack = await targetPack(manifest: {'min_engine_version': 2});
      expect(await failureOf(pack), PackFailure.unsupported);
      expect(await db.contentDao.packs(), isEmpty);
    });

    test('refuses a pack whose normalization examples fail here', () async {
      final pack = await targetPack(
        normalization: {
          ...soundNormalization,
          'tests': [
            ['Bada Kolu.', 'BADA KOLU'],
          ],
        },
      );
      expect(await failureOf(pack), PackFailure.unsupported);
    });

    test(
      'refuses a file that is another pack than the registry says',
      () async {
        final pack = await targetPack();
        final other = pack.info.copyWith(id: 'zz@9');
        expect(
          await importer.import(pack.bytes, other),
          isA<Err<void, PackFailure>>().having(
            (e) => e.error,
            'error',
            PackFailure.damaged,
          ),
        );
      },
    );

    test('refuses bytes that are not a pack, keeping what is there', () async {
      expect(await failureOf(await targetPack()), isNull);
      final before = await keys();
      final garbage = (
        info: (await targetPack(id: 'zz@2', version: 2)).info,
        bytes: Uint8List.fromList(List.filled(4096, 7)),
      );

      expect(await failureOf(garbage), PackFailure.damaged);

      expect(await keys(), before);
      expect((await db.contentDao.packs()).single.packId, 'zz@1');
      // The database is usable afterwards: nothing stays attached.
      expect(await failureOf(await pairPack()), isNull);
    });

    test('tells watchers that the content changed', () async {
      final packs = db.contentDao.watchPacks().map(
        (rows) => [for (final row in rows) row.packId],
      );
      final seen = expectLater(
        packs,
        emitsInOrder([
          <String>[],
          ['zz@1'],
        ]),
      );
      await pumpEventQueue();
      expect(await failureOf(await targetPack()), isNull);
      await seen;
    });
  });
}
