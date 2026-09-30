import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/pack_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_pack_remote.dart';
import '../../helpers/pack_fixture.dart';

void main() {
  late AppDatabase db;
  late FakePackRemote remote;
  late PackRepository repository;

  setUp(() {
    db = memoryDatabase();
    remote = FakePackRemote();
    repository = PackRepository(
      remote: remote,
      importer: PackImporter(db),
      content: db.contentDao,
    );
  });

  tearDown(() => db.close());

  Future<Object> sync() async =>
      switch (await repository.sync(l2: 'zz', l1: 'qq')) {
        Ok(:final value) => value,
        Err(:final error) => error,
      };

  Future<bool> hasContent() => repository.hasContent(l2: 'zz', l1: 'qq');

  group('PackRepository.sync (docs/11-language-packs.md §5)', () {
    test('downloads and imports the course packs once', () async {
      remote
        ..publish(await targetPack())
        ..publish(await pairPack());
      expect(await hasContent(), isFalse);

      expect(await sync(), ['zz@1', 'qq-zz@1']);

      expect(await hasContent(), isTrue);
      expect(await db.contentDao.item('zz.ws.bada.n.1'), isNotNull);
      // Up to date: nothing is downloaded again.
      expect(await sync(), isEmpty);
      expect(remote.downloaded, ['zz@1', 'qq-zz@1']);
    });

    test('takes the newest version and only what changed', () async {
      remote
        ..publish(await targetPack())
        ..publish(await pairPack());
      await sync();
      remote.publish(await targetPack(id: 'zz@2', version: 2, word: 'mire'));

      expect(await sync(), ['zz@2']);

      expect(await db.contentDao.item('zz.ws.mire.n.1'), isNotNull);
      expect(await db.contentDao.item('zz.ws.bada.n.1'), isNull);
    });

    test('a rebuilt pack with the same id is fetched again', () async {
      remote
        ..publish(await targetPack())
        ..publish(await pairPack());
      await sync();
      final rebuilt = FakePackRemote([
        await targetPack(word: 'mire'),
        await pairPack(),
      ]);
      final again = PackRepository(
        remote: rebuilt,
        importer: PackImporter(db),
        content: db.contentDao,
      );

      expect((await again.sync(l2: 'zz', l1: 'qq') as Ok).value, ['zz@1']);
      expect(await db.contentDao.item('zz.ws.mire.n.1'), isNotNull);
    });

    test('ignores packs of other courses', () async {
      remote
        ..publish(await targetPack())
        ..publish(await pairPack())
        ..publish(
          await buildPack(id: 'yy@3', kind: 'target', l2: 'yy', version: 3),
        )
        ..publish(
          await buildPack(id: 'ww-zz@5', kind: 'pair', l1: 'ww', version: 5),
        );

      expect(await sync(), ['zz@1', 'qq-zz@1']);
    });

    test('needs both packs to be published', () async {
      remote.publish(await targetPack());
      expect(await sync(), PackFailure.missing);
      expect(remote.downloaded, isEmpty);
      expect(await hasContent(), isFalse);
    });

    test('a file that does not match its checksum is not imported', () async {
      final target = await targetPack();
      remote
        ..publish((
          info: target.info,
          bytes: Uint8List.fromList([...target.bytes]..[100] ^= 1),
        ))
        ..publish(await pairPack());

      expect(await sync(), PackFailure.damaged);
      expect(await db.contentDao.packs(), isEmpty);
    });

    test('passes on a registry or download failure', () async {
      remote
        ..publish(await targetPack())
        ..publish(await pairPack())
        ..registryFailure = PackFailure.network;
      expect(await sync(), PackFailure.network);

      remote
        ..registryFailure = null
        ..downloadFailure = PackFailure.unknown;
      expect(await sync(), PackFailure.unknown);
      expect(await hasContent(), isFalse);
    });

    test('passes on an import failure', () async {
      remote
        ..publish(await targetPack(formatVersion: 2))
        ..publish(await pairPack());
      expect(await sync(), PackFailure.unsupported);
    });
  });
}
