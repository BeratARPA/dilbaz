import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder_stub.dart'
    if (dart.library.io) 'package:dilbaz_app/data/audio/answer_recorder_io.dart';
import 'package:record/record.dart';

/// A spoken answer, ready to be recognized.
typedef RecordedAudio = ({
  Uint8List bytes,

  /// Media type of [bytes], such as `audio/mp4`.
  String contentType,
  Duration duration,
});

/// Why recording could not start.
enum RecordFailure {
  /// The system did not let the app use the microphone.
  permission,

  /// This platform cannot record yet.
  unsupported,

  /// The microphone could not be opened.
  device,
}

/// Records spoken answers (docs/08-speech.md §4). A card answer is kept
/// only until it is recognized: the file is removed as soon as it is read
/// (docs/08 §5.1).
abstract interface class AnswerRecorder {
  /// The recorder of this platform.
  factory(AudioRecorder recorder) = PlatformAnswerRecorder;

  /// Starts recording.
  Future<Result<void, RecordFailure>> start();

  /// Stops and hands over what was said; null if nothing was recorded.
  Future<RecordedAudio?> stop();

  /// Throws away what is being recorded.
  Future<void> cancel();

  /// Loudness while recording, from 0 (silence) to 1.
  Stream<double> level();

  Future<void> dispose();
}

/// Loudness from 0 to 1 of a level in dBFS: -60 dB and below is silence.
double loudness(double dbfs) {
  if (dbfs.isNaN || dbfs <= -60) return 0;
  if (dbfs >= 0) return 1;
  return (dbfs + 60) / 60;
}
