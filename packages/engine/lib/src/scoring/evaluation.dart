import 'package:dilbaz_engine/src/scoring/verdict.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'evaluation.freezed.dart';

/// The evaluation of one answer, deterministic or by the LLM
/// (docs/03-activities.md §0.2 and §0.5).
@freezed
abstract class Evaluation with _$Evaluation {
  /// Creates an evaluation.
  const factory({
    /// What the answer is.
    required Verdict verdict,

    /// The target came through (`target_ok`): a correct answer uses the
    /// target, an error leaves the target intact.
    required bool targetOk,

    /// Undecided by the deterministic evaluation while the LLM is out of
    /// reach; the LLM result comes later (`llm.pending`).
    @Default(false) bool llmPending,
  }) = _Evaluation;
}
