import 'dart:io';
import 'dart:typed_data';

import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/tasks/recording_store.dart';

/// Keeps recordings as files under `recordings/` in [_directory].
class PlatformRecordingStore implements RecordingStore {
  new({required this._directory});

  final Future<String> Function() _directory;

  @override
  Future<String?> save(String id, RecordedAudio audio) async {
    try {
      final folder = Directory('${await _directory()}/recordings');
      await folder.create(recursive: true);
      final path =
          '${folder.path}/$id.${recordingExtension(audio.contentType)}';
      await File(path).writeAsBytes(audio.bytes, flush: true);
      return path;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<Uint8List?> read(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
