import 'dart:async';

import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/pack_repository_provider.dart';
import 'package:dilbaz_app/features/content/application/content_controller.dart';
import 'package:dilbaz_app/features/content/application/content_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_pack_remote.dart';
import '../../helpers/pack_fixture.dart';

/// The course packs of the app's default course.
Future<List<BuiltPack>> coursePacks({String word = 'bada'}) async => [
  await buildPack(
    id: 'en@1',
    kind: 'target',
    l2: 'en',
    items: [
      item('en.ws.$word.n.1', 'word_sense', packId: 'en@1', text: word),
      item('en.chunk.$word', 'chunk', packId: 'en@1', text: word),
      item('en.sent.1', 'sentence', packId: 'en@1', text: word),
      item('en.sent.2', 'sentence', packId: 'en@1', text: word),
    ],
  ),
  await buildPack(id: 'tr-en@1', kind: 'pair', l2: 'en', l1: 'tr'),
];

void main() {
  late AppDatabase db;
  late FakePackRemote remote;
  late ProviderContainer container;

  setUp(() {
    db = memoryDatabase();
    remote = FakePackRemote();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        packRemoteProvider.overrideWithValue(remote),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<ContentStatus> status() =>
      container.read(contentControllerProvider.future);

  /// Completes once the controller reports [expected].
  Future<void> reaches(ContentStatus expected) {
    final reached = Completer<void>();
    final subscription = container.listen(contentControllerProvider, (_, next) {
      if (next == AsyncData(expected) && !reached.isCompleted) {
        reached.complete();
      }
    }, fireImmediately: true);
    return reached.future.whenComplete(subscription.close);
  }

  const ready = ContentStatus.ready(words: 1, chunks: 1, sentences: 2);

  group('ContentController (docs/11-language-packs.md §5)', () {
    test('fetches the course packs on first use', () async {
      (await coursePacks()).forEach(remote.publish);

      expect(await status(), ready);
      expect(remote.downloaded, ['en@1', 'tr-en@1']);
    });

    test('without content and without a connection nothing is ready', () async {
      remote.registryFailure = PackFailure.network;

      expect(
        await status(),
        const ContentStatus.unavailable(PackFailure.network),
      );
    });

    test('retry fetches once the connection is back', () async {
      (await coursePacks()).forEach(remote.publish);
      remote.registryFailure = PackFailure.network;
      await status();

      remote.registryFailure = null;
      await container.read(contentControllerProvider.notifier).retry();

      expect(container.read(contentControllerProvider).value, ready);
    });

    test('content on the device is ready at once, even offline', () async {
      (await coursePacks()).forEach(remote.publish);
      await status();
      container.invalidate(contentControllerProvider);
      remote.registryFailure = PackFailure.network;

      expect(await status(), ready);
      await pumpEventQueue();
      expect(container.read(contentControllerProvider).value, ready);
    });

    test('a newer pack arrives in the background', () async {
      (await coursePacks()).forEach(remote.publish);
      await status();
      container.invalidate(contentControllerProvider);
      final newer = await buildPack(
        id: 'en@2',
        kind: 'target',
        l2: 'en',
        version: 2,
        items: [item('en.ws.mire.n.1', 'word_sense', packId: 'en@2')],
      );
      remote.publish(newer);

      // First what is on the device, then the refreshed content. The
      // refresh writes a file, so it is waited for rather than timed.
      expect(await status(), ready);
      await reaches(
        const ContentStatus.ready(words: 1, chunks: 0, sentences: 0),
      );
    });
  });
}
