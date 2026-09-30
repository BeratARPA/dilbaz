import 'dart:async';
import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';

/// A recorder that records a few bytes, or fails as told.
class FakeAnswerRecorder implements AnswerRecorder {
  /// Why the next recording cannot start; null means it can.
  RecordFailure? failure;

  /// Whether the next stop hands over nothing.
  bool silent = false;

  int starts = 0;
  int cancels = 0;
  bool recording = false;
  final levels = StreamController<double>.broadcast();

  @override
  Future<Result<void, RecordFailure>> start() async {
    starts++;
    final failure = this.failure;
    if (failure != null) return Err(failure);
    recording = true;
    return const Ok(null);
  }

  @override
  Future<RecordedAudio?> stop() async {
    if (!recording) return null;
    recording = false;
    if (silent) return null;
    return (
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'audio/mp4',
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Future<void> cancel() async {
    cancels++;
    recording = false;
  }

  @override
  Stream<double> level() => levels.stream;

  @override
  Future<void> dispose() async {}
}

/// A recognizer that hears one sentence, or fails as told.
class FakeSpeechRepository implements SpeechRepository {
  new({this.heard = 'he go to work'});

  String heard;

  /// Why the next recognitions fail; null means they work.
  SpeechFailure? failure;
  final asked = <RecordedAudio>[];

  @override
  Future<Result<Transcript, SpeechFailure>> transcribe(
    RecordedAudio audio, {
    String lang = 'en',
  }) async {
    asked.add(audio);
    final failure = this.failure;
    if (failure != null) return Err(failure);
    return Ok(
      Transcript(
        text: heard,
        provider: 'fake',
        model: 'fake',
        durationMs: audio.duration.inMilliseconds,
      ),
    );
  }
}
