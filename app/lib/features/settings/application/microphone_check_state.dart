import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'microphone_check_state.freezed.dart';

/// Where the microphone check is.
@freezed
sealed class MicrophoneCheckState with _$MicrophoneCheckState {
  /// The learner did not consent to recording (docs/14 §4): answers are
  /// typed and nothing is recorded.
  const factory noConsent() = MicrophoneCheckNoConsent;

  /// Ready to record; shows what the last try found.
  const factory ready({
    Transcript? heard,
    SpeechFailure? failure,
    RecordFailure? recordFailure,
  }) = MicrophoneCheckReady;

  const factory recording() = MicrophoneCheckRecording;

  /// Waiting for the speech function.
  const factory recognizing() = MicrophoneCheckRecognizing;
}
