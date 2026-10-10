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

  Future<String> _here(String audioPath) async =>
      '${await _directory()}/recordings/${audioPath.split('/').last}';

  @override
  Future<String?> find(String audioPath) async {
    for (final path in [audioPath, await _here(audioPath)]) {
      if (File(path).isAbsolute && File(path).existsSync()) return path;
    }
    return null;
  }

  @override
  Future<String?> keepFetched(String audioPath, Uint8List bytes) async {
    try {
      final path = await _here(audioPath);
      await File(path).parent.create(recursive: true);
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    } on FileSystemException {
      return null;
    }
  }
}
