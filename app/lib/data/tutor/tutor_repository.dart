import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/data/tutor/annotated_speech.dart';
import 'package:dilbaz_app/data/tutor/answer_check_request.dart';
import 'package:dilbaz_app/data/tutor/gap_suggest_request.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:dilbaz_app/data/tutor/pron_check.dart';
import 'package:dilbaz_app/data/tutor/speaking_annotate_request.dart';
import 'package:json_annotation/json_annotation.dart'
    show CheckedFromJsonException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why the tutor gave no answer. A card then judges without it (docs/03
/// §0.5 step 4, docs/07-ai-tutor.md §7); a capture waits for a later try.
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

  /// The English for what the learner could not say (A19).
  Future<Result<GapSuggestion, TutorFailure>> gapSuggest(
    GapSuggestRequest request,
  );

  /// Marks a speaking task's transcript (A11, A23).
  Future<Result<AnnotatedSpeech, TutorFailure>> speakingAnnotate(
    SpeakingAnnotateRequest request,
  );

  /// Hears a shadowed sentence (A07, ADR-0011).
  Future<Result<HeardPronunciation, TutorFailure>> pronCheck(
    PronCheckRequest request,
  );
}

class SupabaseTutorRepository implements TutorRepository {
  const new(
    this._client, {
    this._wait = answerCheckWait,
    this._gapWait = gapSuggestWait,
    this._annotateWait = speakingAnnotateWait,
    this._pronWait = pronCheckWait,
  });

  final SupabaseClient _client;
  final Duration _wait;
  final Duration _gapWait;
  final Duration _annotateWait;
  final Duration _pronWait;

  /// How long a card waits for the check: the route's limit for one model
  /// (docs/07 §3). After it the request is cut off and the card judges
  /// without the LLM.
  static const answerCheckWait = Duration(seconds: 15);

  /// How long a capture waits for its suggestion: a model and a simplify
  /// call. After it the capture keeps waiting for a later try.
  static const gapSuggestWait = Duration(seconds: 25);

  /// How long a speaking task waits for its marks: two models of up to a
  /// minute each. After it the marks wait for a later try, and the
  /// feedback starts from the word times alone.
  static const speakingAnnotateWait = Duration(seconds: 100);

  /// How long a shadowed sentence waits to be heard: one model of up to
  /// half a minute. After it the sentence shows what was recognized only.
  static const pronCheckWait = Duration(seconds: 35);

  static const _answerCheck = 'tutor/answer_check';
  static const _gapSuggest = 'tutor/gap_suggest';
  static const _speakingAnnotate = 'tutor/speaking_annotate';
  static const _pronCheck = 'tutor/pron_check';

  @override
  Future<Result<LlmAnswerCheck, TutorFailure>> answerCheck(
    AnswerCheckRequest request,
  ) => _call(_answerCheck, request.toJson(), _wait, LlmAnswerCheck.fromJson);

  @override
  Future<Result<GapSuggestion, TutorFailure>> gapSuggest(
    GapSuggestRequest request,
  ) => _call(_gapSuggest, request.toJson(), _gapWait, GapSuggestion.fromJson);

  @override
  Future<Result<AnnotatedSpeech, TutorFailure>> speakingAnnotate(
    SpeakingAnnotateRequest request,
  ) => _call(
    _speakingAnnotate,
    request.toJson(),
    _annotateWait,
    AnnotatedSpeech.fromJson,
  );

  @override
  Future<Result<HeardPronunciation, TutorFailure>> pronCheck(
    PronCheckRequest request,
  ) => _call(
    _pronCheck,
    request.toJson(),
    _pronWait,
    HeardPronunciation.read,
  );

  Future<Result<T, TutorFailure>> _call<T>(
    String route,
    Map<String, Object?> body,
    Duration wait,
    T Function(Map<String, Object?> json) read,
  ) async {
    try {
      final response = await _client.functions.invoke(
        route,
        body: body,
        abortSignal: Future<void>.delayed(wait),
      );
      return switch (response.data) {
        final Map<String, Object?> json => Ok<T, TutorFailure>(read(json)),
        _ => Err<T, TutorFailure>(TutorFailure.invalid),
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
    'missing_text' ||
    'unsupported_pair' => TutorFailure.invalid,
    _ => TutorFailure.unknown,
  },
  _ => TutorFailure.unknown,
};
