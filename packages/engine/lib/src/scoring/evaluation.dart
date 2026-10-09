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

  const new _();

  /// The LLM's evaluation with the target of a minor error taken from
  /// [targetIntact], the engine's word on it (`AnswerChecker.targetIntact`):
  /// whether the answer counts for the card turns on it, and the LLM's own
  /// `target_ok` sways with its prompt (ADR-0010). Other verdicts stay.
  Evaluation settled({required bool targetIntact}) =>
      verdict == Verdict.minorError ? copyWith(targetOk: targetIntact) : this;
}
