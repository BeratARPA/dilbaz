import 'package:dilbaz_engine/src/fsrs/review_rating.dart';
import 'package:dilbaz_engine/src/scoring/latency_profile.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'review_outcome.freezed.dart';

/// How the review of one card ended, and its automatic FSRS rating
/// (docs/03-activities.md §0.3; no self-assessment).
@freezed
sealed class ReviewOutcome with _$ReviewOutcome {
  /// The target was produced correctly: production evidence.
  const factory recalled({
    /// On the first attempt, with no hint and without being asked again.
    required bool firstTry,

    /// Latency of the answer that recalled the target.
    required int latencyMs,
  }) = Recalled;

  /// No correct answer within the attempts, or the answer (H4) was opened.
  const factory notRecalled() = NotRecalled;

  /// Only correct answers without the target; the target was shown.
  const factory withoutTarget() = WithoutTarget;

  /// Undecided without the LLM; evidence waits for the LLM result.
  const factory undecided() = Undecided;

  const new _();

  /// Whether the review is evidence that the learner produced the target.
  bool get isEvidence => this is Recalled;

  /// The FSRS rating. Easy needs a first-try recall that is fast for this
  /// learner in this mode ([latencies]), and never comes right after the
  /// item's introduction ([justIntroduced]): the answer was just shown, so
  /// speed says nothing about memory.
  ReviewRating rating(
    LatencyProfile latencies, {
    bool justIntroduced = false,
  }) => switch (this) {
    Recalled(firstTry: true, :final latencyMs) =>
      !justIntroduced && latencies.isFast(latencyMs)
          ? ReviewRating.easy
          : ReviewRating.good,
    Recalled() => ReviewRating.hard,
    // Neither a penalty nor inflation.
    WithoutTarget() || Undecided() => ReviewRating.hard,
    NotRecalled() => ReviewRating.again,
  };
}
