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
