import 'dart:async';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/recorder_config.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/features/settings/application/microphone_check_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'microphone_check_controller.g.dart';

/// A short recording that the speech function writes down, so the learner
/// can hear that the microphone and the recognizer work (docs/06 §3.1:
/// the microphone is checked before a test). Nothing is kept.
@riverpod
class MicrophoneCheckController extends _$MicrophoneCheckController {
  Timer? _limit;

  @override
  Future<MicrophoneCheckState> build() async {
    ref.onDispose(() => _limit?.cancel());
    final userId = ref.watch(authRepositoryProvider).userId;
    final consent =
        userId != null &&
        await ref
            .watch(profileRepositoryProvider)
            .watchAudioConsent(userId)
            .first;
    return consent
        ? const MicrophoneCheckState.ready()
        : const MicrophoneCheckState.noConsent();
  }

  /// Starts recording; it stops by itself at the length of a card answer.
  Future<void> record() async {
    if (state.value is! MicrophoneCheckReady) return;
    final recorder = ref.read(answerRecorderProvider);
    state = const AsyncData(MicrophoneCheckState.recording());
    final started = await recorder.start();
    if (!ref.mounted) return;
    if (started case Err(:final error)) {
      state = AsyncData(MicrophoneCheckState.ready(recordFailure: error));
      return;
    }
    _limit = Timer(RecorderConfig.cardLimit, () => unawaited(stop()));
  }

  /// Stops recording and asks what was heard.
  Future<void> stop() async {
    if (state.value is! MicrophoneCheckRecording) return;
    _limit?.cancel();
    final recorder = ref.read(answerRecorderProvider);
    final speech = ref.read(speechRepositoryProvider);
    state = const AsyncData(MicrophoneCheckState.recognizing());
    final audio = await recorder.stop();
    if (!ref.mounted) return;
    if (audio == null) {
      state = const AsyncData(MicrophoneCheckState.ready());
      return;
    }
    final result = await speech.transcribe(audio);
    if (!ref.mounted) return;
    state = AsyncData(switch (result) {
      Ok(value: final heard) => MicrophoneCheckState.ready(heard: heard),
      Err(:final error) => MicrophoneCheckState.ready(failure: error),
    });
  }
}
