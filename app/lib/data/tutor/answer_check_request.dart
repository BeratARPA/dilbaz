import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'answer_check_request.freezed.dart';

/// A card answer for `tutor/answer_check` (docs/07-ai-tutor.md §4.1). It is
/// sent only after the deterministic check found no match (docs/03 §0.5),
/// so it always carries an answer (I-01, I-11).
@freezed
abstract class AnswerCheckRequest with _$AnswerCheckRequest {
  const factory({
    /// The learner's language and the target language.
    required String l1,
    required String l2,
    required CefrLevel level,

    /// Hints in the learner's language, else in the target's (the level's
    /// scaffolds, docs/02 §3).
    required bool explainInL1,
    required String itemKey,

    /// The prompt in the learner's language and the carrier's text.
    required String prompt,
    required String reference,

    /// The listed correct answers that say the card's target, and those
    /// that do not (`AnswerChecker.listed`).
    required List<String> variants,
    required List<String> alternatives,

    /// The reference's words the card practises.
    required String targetSpan,

    /// The answer, typed or as speech recognition heard it.
    required String answer,
    required bool typed,

    /// Which counted attempt the answer is: 1–3.
    required int attemptNo,
    @Default(<String>[]) List<String> grammarCodes,
    String? contextNote,
    double? asrConfidence,

    /// The review's earlier answers, at most two.
    @Default(<String>[]) List<String> previousResponses,
  }) = _AnswerCheckRequest;

  const new _();

  /// The route's body.
  Map<String, Object?> toJson() => {
    'ctx': {
      'l1': l1,
      'l2': l2,
      'level': level.code,
      'explain_in': explainInL1 ? 'l1' : 'l2',
    },
    'item': {
      'key': itemKey,
      'prompt_l1': prompt,
      'reference_l2': reference,
      'variants': variants,
      'alternatives': alternatives,
      'target_span': targetSpan,
      'grammar_codes': grammarCodes,
      'context_note': ?contextNote,
    },
    'response': {
      'text': answer,
      'source': typed ? 'typed' : 'asr',
      'asr_confidence': ?asrConfidence,
    },
    'attempt_no': attemptNo,
    'previous_responses': previousResponses,
  };
}
