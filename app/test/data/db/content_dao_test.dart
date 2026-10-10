import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pack_fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = memoryDatabase();
    final importer = PackImporter(db);
    for (final pack in [await targetPack(), await pairPack()]) {
      await importer.import(pack.bytes, pack.info);
    }
  });

  tearDown(() => db.close());

  group('ContentDao', () {
    test('counts the items of each kind', () async {
      expect(await db.contentDao.itemCounts(), {
        'word_sense': 2,
        'chunk': 1,
        'sentence': 1,
        'lemma': 1,
      });
    });

    test('lists items of the kinds asked for, by key', () async {
      final rows = await db.contentDao.itemsOfKinds(['word_sense', 'chunk']);
      expect(
        [for (final row in rows) row.key],
        ['zz.chunk.bada_kolu', 'zz.ws.bada.n.1', 'zz.ws.kolu.v.1'],
      );
      expect(rows[1].rank, 12);
      expect(rows[1].data['carriers'], ['zz.sent.0001']);
    });

    test('finds an item by key', () async {
      expect((await db.contentDao.item('zz.ws.kolu.v.1'))!.textL2, 'kolu');
      expect(await db.contentDao.item('zz.ws.none.n.1'), isNull);
    });

    test('reads links of one type from both packs', () async {
      final contains = await db.contentDao.linksOfType('contains');
      expect(contains.single.fromKey, 'zz.sent.0001');
      expect(contains.single.packId, 'zz@1');
      final contrasts = await db.contentDao.linksOfType('contrasts_with');
      expect(contrasts.single.packId, 'qq-zz@1');
      expect(await db.contentDao.linksOfType('requires'), isEmpty);
    });

    test('builds the forms table', () async {
      expect(await db.contentDao.forms(), {
        'bada': {'bada'},
        'badaven': {'bada'},
        'kolu': {'kolu'},
      });
    });

    test('reads pair entries by kind and key', () async {
      expect(await db.contentDao.pairEntry('variants', 'zz.sent.0001'), {
        'variants': ['Kolu bada.'],
      });
      expect(await db.contentDao.pairEntry('gloss', 'zz.sent.0001'), isNull);
    });
  });
}
