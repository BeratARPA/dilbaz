import 'dart:typed_data';

import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/tasks/recording_store_stub.dart'
    if (dart.library.io) 'package:dilbaz_app/data/tasks/recording_store_io.dart';

/// The audio of task and test recordings on this device (docs/08-speech.md
/// §5.2): kept for listening back and comparing months (docs/06 §3.4),
/// only for their owner (I-18). A card answer is never kept here.
abstract interface class RecordingStore {
  /// The store of this platform; [directory] is where recordings are kept.
  factory({required Future<String> Function() directory}) =
      PlatformRecordingStore;

  /// Keeps [audio] as the recording [id]; its path, or null where audio
  /// cannot be kept (web).
  Future<String?> save(String id, RecordedAudio audio);

  /// The audio at [path]; null when it is gone.
  Future<Uint8List?> read(String path);

  Future<void> delete(String path);
}

/// The file name ending of a recording's media type.
String recordingExtension(String contentType) => switch (contentType) {
  'audio/webm' => 'webm',
  'audio/ogg' => 'ogg',
  'audio/wav' => 'wav',
  _ => 'm4a',
};
