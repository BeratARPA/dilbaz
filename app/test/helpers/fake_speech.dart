import 'dart:async';
import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/dictation.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';

/// A recorder that records a few bytes, or fails as told.
class FakeAnswerRecorder implements AnswerRecorder {
  /// Why the next recording cannot start; null means it can.
  RecordFailure? failure;

  /// Whether the next stop hands over nothing.
  bool silent = false;

  /// How long each recording is.
  Duration duration = const Duration(seconds: 2);

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
      duration: duration,
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
    final words = heard.split(' ').where((w) => w.isNotEmpty);
    return Ok(
      Transcript(
        text: heard,
        provider: 'fake',
        model: 'fake',
        durationMs: audio.duration.inMilliseconds,
        // Each word 400 ms, then 100 ms of silence.
        words: [
          for (final (i, w) in words.indexed)
            TranscriptWord(w: w, startMs: i * 500, endMs: i * 500 + 400),
        ],
      ),
    );
  }
}

/// A dictation that hears one text, or fails as told.
class FakeDictation implements Dictation {
  new({this.heard = 'canım sıkıldı'});

  String heard;

  /// Why the next start or stop fails; null means they work.
  DictationFailure? startFailure;
  DictationFailure? stopFailure;
  int starts = 0;
  int stops = 0;
  int cancels = 0;

  @override
  Future<Result<void, DictationFailure>> start() async {
    starts++;
    final failure = startFailure;
    return failure == null ? const Ok(null) : Err(failure);
  }

  @override
  Future<Result<String, DictationFailure>> stop() async {
    stops++;
    final failure = stopFailure;
    return failure == null ? Ok(heard) : Err(failure);
  }

  @override
  Future<void> cancel() async => cancels++;
}
