import 'dart:io';
import 'dart:typed_data';

import 'package:dilbaz_app/data/tasks/recording_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async => directory = await Directory.systemTemp.createTemp('rec'));
  tearDown(() => directory.delete(recursive: true));

  test('a recording is kept under its id, read back and removed', () async {
    final store = RecordingStore(directory: () async => directory.path);
    final audio = (
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'audio/mp4',
      duration: const Duration(seconds: 70),
    );

    final path = await store.save('rec-1', audio);

    expect(path, endsWith('recordings/rec-1.m4a'));
    expect(await store.read(path!), [1, 2, 3]);
    await store.delete(path);
    expect(await store.read(path), isNull);
    // Removing it twice is no trouble.
    await store.delete(path);
  });

  test(
    'a recording is found by its server path, or fetched and kept',
    () async {
      final store = RecordingStore(directory: () async => directory.path);
      final audio = (
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'audio/mp4',
        duration: const Duration(seconds: 70),
      );
      final kept = await store.save('rec-1', audio);
      expect(await store.find('user/2026/10/rec-1.m4a'), kept);
      // A recording kept before the audio went to the server.
      expect(await store.find(kept!), kept);
      expect(await store.find('user/2026/10/rec-2.m4a'), isNull);

      final fetched = await store.keepFetched(
        'user/2026/09/rec-2.m4a',
        Uint8List.fromList([4]),
      );
      expect(fetched, endsWith('recordings/rec-2.m4a'));
      expect(await store.find('user/2026/09/rec-2.m4a'), fetched);
      expect(await store.read(fetched!), [4]);
    },
  );

  test(
    'a fetched recording is not kept where the folder cannot be written',
    () async {
      final file = File('${directory.path}/not_a_folder')
        ..writeAsStringSync('x');
      final store = RecordingStore(directory: () async => file.path);
      expect(
        await store.keepFetched('user/2026/09/rec-3.m4a', Uint8List(1)),
        isNull,
      );
    },
  );

  test("the server path: the learner's folder, by month", () {
    expect(
      recordingStoragePath(
        userId: 'user',
        id: 'rec-1',
        at: DateTime.utc(2026, 1, 31, 23),
        contentType: 'audio/webm',
      ),
      'user/2026/01/rec-1.webm',
    );
    expect(recordingContentType('u/2026/01/r.m4a'), 'audio/mp4');
    expect(recordingContentType('u/2026/01/r.webm'), 'audio/webm');
    expect(recordingContentType('u/2026/01/r.ogg'), 'audio/ogg');
    expect(recordingContentType('u/2026/01/r.wav'), 'audio/wav');
  });

  test('the media type gives the file name ending', () {
    expect(recordingExtension('audio/mp4'), 'm4a');
    expect(recordingExtension('audio/webm'), 'webm');
    expect(recordingExtension('audio/ogg'), 'ogg');
    expect(recordingExtension('audio/wav'), 'wav');
  });

  test('nothing is kept where the folder cannot be written', () async {
    final file = File('${directory.path}/not_a_folder')..writeAsStringSync('x');
    final store = RecordingStore(directory: () async => file.path);
    final audio = (
      bytes: Uint8List.fromList([1]),
      contentType: 'audio/mp4',
      duration: Duration.zero,
    );
    expect(await store.save('rec-2', audio), isNull);
  });
}
