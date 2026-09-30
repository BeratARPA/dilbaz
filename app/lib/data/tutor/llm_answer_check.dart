import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'llm_answer_check.freezed.dart';
part 'llm_answer_check.g.dart';

/// The hints of an answer that missed, H1–H4. The server blanks a hint
/// that gives the answer away; the card fills it from its own templates
/// (docs/07-ai-tutor.md §4.1).
@freezed
abstract class LlmLadder with _$LlmLadder {
  const factory({
    required String h1,
    required String h2,
    required String h3,
    required String h4,
  }) = _LlmLadder;

  factory fromJson(Map<String, Object?> json) => _$LlmLadderFromJson(json);
}

/// Where an error is in the answer: characters [start] to [end] (end
/// exclusive), with its tag from the pair's closed list.
@freezed
abstract class ErrorSpan with _$ErrorSpan {
  const factory({required int start, required int end, required String tag}) =
      _ErrorSpan;

  factory fromJson(Map<String, Object?> json) => _$ErrorSpanFromJson(json);
}

Verdict _verdict(String code) =>
    Verdict.values.firstWhere((v) => v.code == code);

String _code(Verdict verdict) => verdict.code;

/// What `tutor/answer_check` said about an answer (docs/07-ai-tutor.md
/// §4.1).
@freezed
abstract class LlmAnswerCheck with _$LlmAnswerCheck {
  // Anything off the contract fails as one exception, not a crash. freezed
  // moves the annotation to the generated class.
  // ignore: invalid_annotation_target
  @JsonSerializable(checked: true)
  const factory({
    @JsonKey(fromJson: _verdict, toJson: _code) required Verdict verdict,
    required bool targetOk,
    required List<String> errorTags,
    required List<ErrorSpan> errorSpans,
    required LlmLadder ladder,
    required double confidence,

    /// The pair pack the tags come from, and who answered.
    required String catalog,
    required String provider,
    required String model,

    /// The answer, for `acceptable_variant`: the learner's own correct
    /// answer, remembered for next time (docs/03 §0.5 step 3).
    String? variantToLearn,
  }) = _LlmAnswerCheck;

  const new _();

  factory fromJson(Map<String, Object?> json) => _$LlmAnswerCheckFromJson(json);

  /// The evaluation as the card review reads it.
  Evaluation get evaluation => Evaluation(verdict: verdict, targetOk: targetOk);
}
