import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:record/record.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'speech_providers.g.dart';

/// Requires `Supabase.initialize` (main.dart); tests override it with a fake.
@Riverpod(keepAlive: true)
SpeechRepository speechRepository(Ref ref) =>
    SupabaseSpeechRepository(Supabase.instance.client);

/// The recorder of one screen; it is freed with the screen.
@riverpod
AnswerRecorder answerRecorder(Ref ref) {
  final recorder = AnswerRecorder(AudioRecorder());
  ref.onDispose(recorder.dispose);
  return recorder;
}

/// Loudness while recording, for a level meter.
@riverpod
Stream<double> answerLevel(Ref ref) =>
    ref.watch(answerRecorderProvider).level();
