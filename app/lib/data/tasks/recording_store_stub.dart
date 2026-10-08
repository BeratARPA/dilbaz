import 'dart:typed_data';

import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/tasks/recording_store.dart';

/// Where there is no file system (web), recordings are not kept yet.
class PlatformRecordingStore implements RecordingStore {
  // The parameter keeps the constructor the same on every platform.
  // ignore: avoid_unused_constructor_parameters
  const new({required Future<String> Function() directory});

  @override
  Future<String?> save(String id, RecordedAudio audio) async => null;

  @override
  Future<Uint8List?> read(String path) async => null;

  @override
  Future<void> delete(String path) async {}
}
