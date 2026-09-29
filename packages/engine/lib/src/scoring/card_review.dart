import 'package:dilbaz_engine/src/scoring/answer_effect.dart';
import 'package:dilbaz_engine/src/scoring/evaluation.dart';
import 'package:dilbaz_engine/src/scoring/review_outcome.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'card_review.freezed.dart';

/// One review of a card, from the prompt to the outcome that sets its
/// automatic rating (docs/03-activities.md §0.2–0.3).
///
/// Immutable: every step returns the next state. A missed answer uses up
/// one of [maxAttempts] attempts and opens the next hint (H1, H2, …). After
/// a try the learner may also open the next hint or the answer (H4) on
/// request (I-01, I-02). Opening H4 ends the review.
@freezed
abstract class CardReview with _$CardReview {
  /// A review before its first answer.
  const factory({
    /// Counted attempts allowed; the review ends at this many misses.
    @Default(CardReview.defaultMaxAttempts) int maxAttempts,

    /// Missed answers so far; each used up an attempt.
    @Default(0) int misses,

    /// Highest hint shown: 0 none, 1–3 hints, 4 the answer.
    @Default(0) int hintLevel,

    /// The prompt was asked again after a correct answer without the target.
    @Default(false) bool reprompted,

    /// Effect of the latest answer; null before the first one.
    AnswerEffect? lastEffect,

    /// How the review ended; null while it goes on.
    ReviewOutcome? outcome,
  }) = _CardReview;

  const new _();

  /// Counted attempts per review (A01).
  static const defaultMaxAttempts = 3;

  /// Hint level that shows the answer.
  static const answerLevel = 4;

  /// Whether the review has ended.
  bool get isDone => outcome != null;

  /// Records the [evaluation] of the next answer, given [latencyMs] after
  /// the prompt was shown.
  CardReview answer(Evaluation evaluation, {required int latencyMs}) {
    _requireOpen();
    if (latencyMs < 0) {
      throw ArgumentError.value(latencyMs, 'latencyMs', 'negative');
    }
    final effect = AnswerEffect.of(evaluation);
    final next = copyWith(lastEffect: effect);
    switch (effect) {
      case AnswerEffect.unintelligible:
        return next;
      case AnswerEffect.undecided:
        return next.copyWith(outcome: const ReviewOutcome.undecided());
      case AnswerEffect.recalled:
        // Hints open only after a miss, so no miss means no hint.
        return next.copyWith(
          outcome: ReviewOutcome.recalled(
            firstTry: misses == 0 && !reprompted,
            latencyMs: latencyMs,
          ),
        );
      case AnswerEffect.correctWithoutTarget:
        return reprompted
            ? next.copyWith(outcome: const ReviewOutcome.withoutTarget())
            : next.copyWith(reprompted: true);
      case AnswerEffect.missed:
        final used = next.copyWith(misses: misses + 1);
        return used.misses < maxAttempts
            ? used._show(hintLevel + 1)
            : used.copyWith(outcome: const ReviewOutcome.notRecalled());
    }
  }

  /// Opens the next hint of the ladder; there is one only after a miss.
  CardReview nextHint() {
    _requireOpen();
    if (hintLevel == 0) throw StateError('no_hint_before_a_miss');
    return _show(hintLevel + 1);
  }

  /// Opens the answer (H4) at the learner's request, only after a try.
  CardReview reveal() {
    _requireOpen();
    if (misses == 0 && !reprompted) throw StateError('no_answer_before_a_try');
    return _show(answerLevel);
  }

  CardReview _show(int level) {
    if (level < answerLevel) return copyWith(hintLevel: level);
    return copyWith(
      hintLevel: answerLevel,
      // After nothing but correct answers without the target, showing the
      // target is neither a penalty nor evidence.
      outcome: misses == 0 && reprompted
          ? const ReviewOutcome.withoutTarget()
          : const ReviewOutcome.notRecalled(),
    );
  }

  void _requireOpen() {
    if (isDone) throw StateError('review_done');
  }
}
