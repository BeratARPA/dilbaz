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

  /// A body made by [toJson], kept with an attempt to ask again later.
  factory fromJson(Map<String, Object?> json) {
    final ctx = json['ctx']! as Map<String, Object?>;
    final item = json['item']! as Map<String, Object?>;
    final response = json['response']! as Map<String, Object?>;
    List<String> strings(Object? value) =>
        (value! as List<Object?>).cast<String>();
    return AnswerCheckRequest(
      l1: ctx['l1']! as String,
      l2: ctx['l2']! as String,
      level: CefrLevel.values.firstWhere((l) => l.code == ctx['level']),
      explainInL1: ctx['explain_in'] == 'l1',
      itemKey: item['key']! as String,
      prompt: item['prompt_l1']! as String,
      reference: item['reference_l2']! as String,
      variants: strings(item['variants']),
      alternatives: strings(item['alternatives']),
      targetSpan: item['target_span']! as String,
      grammarCodes: strings(item['grammar_codes']),
      contextNote: item['context_note'] as String?,
      answer: response['text']! as String,
      typed: response['source'] == 'typed',
      asrConfidence: (response['asr_confidence'] as num?)?.toDouble(),
      attemptNo: json['attempt_no']! as int,
      previousResponses: strings(json['previous_responses']),
    );
  }

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
