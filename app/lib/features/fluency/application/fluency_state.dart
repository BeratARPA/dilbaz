import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'fluency_state.freezed.dart';

/// A topic to tell: a task the learner has spoken about.
typedef FluencyTopic = ({String key, String title});

/// What one round measured; the measures are null when the round could
/// not be written down. Counts, not percentages (I-04).
typedef RoundResult = ({
  int number,
  Duration limit,
  Duration spoken,
  int? words,
  double? speechRate,
  double? longPausesPerMin,
});

/// Where a 4/3/2 is (A12, docs/09 §5.7).
@freezed
sealed class FluencyState with _$FluencyState {
  /// No course, profile or packs on the device yet.
  const factory unavailable() = FluencyUnavailable;

  /// The learner has not agreed to audio recordings (I-18).
  const factory needsConsent() = FluencyNeedsConsent;

  /// No task spoken about yet: 4/3/2 takes a known topic (A12 step 1).
  const factory noTopic() = FluencyNoTopic;

  /// The topics to choose from, best first (I-14), and the rounds' times.
  const factory choosing({
    required List<FluencyTopic> topics,
    required List<Duration> rounds,
  }) = FluencyChoosing;

  /// Round [number] of three: the topic's card and its time.
  const factory round({
    required TaskView task,
    required int number,
    required bool recording,
  }) = FluencyRound;

  /// The round is being written down.
  const factory checking() = FluencyChecking;

  /// The round could not be used: nothing heard, or no microphone.
  const factory failed({
    required int number,
    required SpeakingFailure failure,
  }) = FluencyFailed;

  /// Between rounds: what the rounds so far measured, and the next time.
  const factory between({
    required List<RoundResult> results,
    required Duration next,
  }) = FluencyBetween;

  /// The three rounds, side by side.
  const factory done({required List<RoundResult> results}) = FluencyDone;
}
