import 'package:dilbaz_engine/src/scoring/evaluation.dart';
import 'package:dilbaz_engine/src/scoring/verdict.dart';

/// What an evaluated answer does to the card under review
/// (docs/03-activities.md §0.2).
enum AnswerEffect {
  /// The target was produced correctly; ends the review.
  recalled,

  /// Correct, but without the target: neither an error nor evidence. The
  /// prompt is asked once more without using up an attempt or a hint.
  correctWithoutTarget,

  /// The target was not produced correctly; uses up an attempt.
  missed,

  /// Nothing usable was heard; not counted. The learner records again or
  /// types the answer.
  unintelligible,

  /// Undecided without the LLM; ends the review with no evidence.
  undecided;

  /// Effect of [evaluation].
  static AnswerEffect of(Evaluation evaluation) => switch (evaluation) {
    Evaluation(verdict: Verdict.unintelligible) => unintelligible,
    Evaluation(verdict: Verdict.uncertain, llmPending: true) => undecided,
    // Still uncertain after "did you mean …?": counted as correct, and the
    // item goes to content review.
    Evaluation(verdict: Verdict.uncertain) => recalled,
    Evaluation(
      verdict: Verdict.correct || Verdict.acceptableVariant,
      targetOk: false,
    ) =>
      correctWithoutTarget,
    Evaluation(
      verdict: Verdict.correct ||
          Verdict.acceptableVariant ||
          Verdict.minorError,
      targetOk: true,
    ) =>
      recalled,
    // An error in the target, a wrong answer or something else said.
    Evaluation() => missed,
  };
}
