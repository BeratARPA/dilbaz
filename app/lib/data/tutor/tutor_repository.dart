import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/tutor/answer_check_request.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:json_annotation/json_annotation.dart'
    show CheckedFromJsonException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why the tutor gave no answer. The card then judges without it
/// (docs/03 §0.5 step 4, docs/07-ai-tutor.md §7).
enum TutorFailure {
  /// No connection, or no answer in time.
  network,

  /// The learner's share of today's free quota is used up.
  quota,

  /// No model is set up, or none the learner allows.
  unavailable,

  /// Every model refused the text.
  refused,

  /// No model gave a valid answer.
  failed,

  /// The request or the answer is off the contract.
  invalid,

  unknown,
}

/// The LLM routes of the `tutor` function (docs/07-ai-tutor.md §4).
abstract interface class TutorRepository {
  /// Judges a card answer the deterministic check could not match.
  Future<Result<LlmAnswerCheck, TutorFailure>> answerCheck(
    AnswerCheckRequest request,
  );
}

class SupabaseTutorRepository implements TutorRepository {
  const new(this._client, {this._wait = answerCheckWait});

  final SupabaseClient _client;
  final Duration _wait;

  /// How long a card waits for the check: the route's limit for one model
  /// (docs/07 §3). After it the request is cut off and the card judges
  /// without the LLM.
  static const answerCheckWait = Duration(seconds: 15);

  static const _answerCheck = 'tutor/answer_check';

  @override
  Future<Result<LlmAnswerCheck, TutorFailure>> answerCheck(
    AnswerCheckRequest request,
  ) async {
    try {
      final response = await _client.functions.invoke(
        _answerCheck,
        body: request.toJson(),
        abortSignal: Future<void>.delayed(_wait),
      );
      return switch (response.data) {
        final Map<String, Object?> json => Ok(LlmAnswerCheck.fromJson(json)),
        _ => const Err(TutorFailure.invalid),
      };
    } on RequestAbortedException {
      return const Err(TutorFailure.network);
    } on FunctionsFetchException {
      return const Err(TutorFailure.network);
    } on FunctionException catch (error) {
      return Err(tutorFailure(error.details));
    } on CheckedFromJsonException {
      return const Err(TutorFailure.invalid);
    } on FormatException {
      // A success whose body is not JSON.
      return const Err(TutorFailure.invalid);
    }
  }
}

/// Maps the stable error code of the `tutor` function (docs/07 §4.1).
TutorFailure tutorFailure(Object? details) => switch (details) {
  {'error': {'code': final String code}} => switch (code) {
    'quota_exhausted' => TutorFailure.quota,
    'llm_unavailable' => TutorFailure.unavailable,
    'llm_refused' => TutorFailure.refused,
    'llm_failed' => TutorFailure.failed,
    'bad_json' ||
    'invalid_input' ||
    'missing_response' ||
    'unsupported_pair' => TutorFailure.invalid,
    _ => TutorFailure.unknown,
  },
  _ => TutorFailure.unknown,
};
