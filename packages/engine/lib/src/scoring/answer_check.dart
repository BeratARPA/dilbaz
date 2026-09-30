import 'package:dilbaz_engine/src/scoring/evaluation.dart';
import 'package:dilbaz_engine/src/scoring/hint_ladder.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'answer_check.freezed.dart';

/// The deterministic check of one answer: its evaluation and, for a miss,
/// the templated hints.
@freezed
abstract class AnswerCheck with _$AnswerCheck {
  /// Creates a check.
  const factory({
    /// What the answer is.
    required Evaluation evaluation,

    /// Hints for the next attempt; null unless the answer missed.
    HintLadder? ladder,
  }) = _AnswerCheck;
}
