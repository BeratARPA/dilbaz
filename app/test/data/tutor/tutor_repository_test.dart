import 'dart:convert';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/data/tutor/annotated_speech.dart';
import 'package:dilbaz_app/data/tutor/answer_check_request.dart';
import 'package:dilbaz_app/data/tutor/gap_suggest_request.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:dilbaz_app/data/tutor/speaking_annotate_request.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const request = AnswerCheckRequest(
  l1: 'tr',
  l2: 'en',
  level: CefrLevel.a2,
  explainInL1: true,
  itemKey: 'en.ws.forget.v.1',
  prompt: 'Ekmek almayı unutma!',
  reference: "Don't forget to buy bread!",
  variants: ['Do not forget to buy bread!'],
  alternatives: ['Remember to buy bread!'],
  targetSpan: 'forget',
  answer: 'Dont forgot buy bread',
  typed: true,
  attemptNo: 2,
  grammarCodes: ['gp.en.imperative_negative'],
  previousResponses: ['Not forget bread'],
);

const Map<String, Object?> answer = {
  'verdict': 'wrong',
  'target_ok': false,
  'error_tags': ['verb_form'],
  'error_spans': [
    {'start': 5, 'end': 11, 'tag': 'verb_form'},
  ],
  'ladder': {'h1': 'Fiil biçimi', 'h2': 'İkinci kelime', 'h3': '', 'h4': 'x'},
  'variant_to_learn': null,
  'confidence': 0.9,
  'catalog': 'tr-en@1',
  'provider': 'gemini',
  'model': 'gemini-3.1-flash-lite',
};

SupabaseTutorRepository repositoryWith(MockClientHandler handler) =>
    SupabaseTutorRepository(
      SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test',
        httpClient: MockClient(handler),
      ),
    );

Response json(Request request, int status, Object? body) => Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
  request: request,
);

void main() {
  gapSuggestTests();
  speakingAnnotateTests();
  test('a request kept with its attempt reads back the same', () {
    expect(AnswerCheckRequest.fromJson(request.toJson()), request);
    final heard = request.copyWith(
      typed: false,
      asrConfidence: 0.75,
      contextNote: 'Arkadaşına',
      grammarCodes: const [],
      previousResponses: const [],
    );
    expect(AnswerCheckRequest.fromJson(heard.toJson()), heard);
  });

  group('SupabaseTutorRepository (docs/07-ai-tutor.md §4.1)', () {
    test('sends the route its body and reads the verdict', () async {
      late Request seen;
      final repository = repositoryWith((sent) async {
        seen = sent;
        return json(sent, 200, answer);
      });

      final result = await repository.answerCheck(request);

      final check = (result as Ok<LlmAnswerCheck, TutorFailure>).value;
      expect(
        check,
        const LlmAnswerCheck(
          verdict: Verdict.wrong,
          targetOk: false,
          errorTags: ['verb_form'],
          errorSpans: [ErrorSpan(start: 5, end: 11, tag: 'verb_form')],
          ladder: LlmLadder(
            h1: 'Fiil biçimi',
            h2: 'İkinci kelime',
            h3: '',
            h4: 'x',
          ),
          confidence: 0.9,
          catalog: 'tr-en@1',
          provider: 'gemini',
          model: 'gemini-3.1-flash-lite',
        ),
      );
      expect(
        check.evaluation,
        const Evaluation(verdict: Verdict.wrong, targetOk: false),
      );
      expect(seen.url.path, '/functions/v1/tutor/answer_check');
      expect(jsonDecode(seen.body), {
        'ctx': {'l1': 'tr', 'l2': 'en', 'level': 'A2', 'explain_in': 'l1'},
        'item': {
          'key': 'en.ws.forget.v.1',
          'prompt_l1': 'Ekmek almayı unutma!',
          'reference_l2': "Don't forget to buy bread!",
          'variants': ['Do not forget to buy bread!'],
          'alternatives': ['Remember to buy bread!'],
          'target_span': 'forget',
          'grammar_codes': ['gp.en.imperative_negative'],
        },
        'response': {'text': 'Dont forgot buy bread', 'source': 'typed'},
        'attempt_no': 2,
        'previous_responses': ['Not forget bread'],
      });
    });

    test('a heard answer goes with its confidence, a note with the item', () {
      final body = request
          .copyWith(
            typed: false,
            asrConfidence: 0.8,
            contextNote: 'arkadaşına',
            explainInL1: false,
          )
          .toJson();
      expect(body['response'], {
        'text': 'Dont forgot buy bread',
        'source': 'asr',
        'asr_confidence': 0.8,
      });
      expect((body['item']! as Map)['context_note'], 'arkadaşına');
      expect((body['ctx']! as Map)['explain_in'], 'l2');
    });

    test('an acceptable variant comes with the answer to learn', () async {
      final repository = repositoryWith(
        (sent) async => json(sent, 200, {
          ...answer,
          'verdict': 'acceptable_variant',
          'target_ok': true,
          'error_tags': <String>[],
          'error_spans': <Object>[],
          'ladder': {'h1': '', 'h2': '', 'h3': '', 'h4': ''},
          'variant_to_learn': 'Do not forget bread!',
          'confidence': 1,
        }),
      );
      final check = (await repository.answerCheck(
        request,
      ) as Ok<LlmAnswerCheck, TutorFailure>).value;
      expect(check.verdict, Verdict.acceptableVariant);
      expect(check.variantToLearn, 'Do not forget bread!');
      expect(check.confidence, 1.0);
    });

    test('the codes of the function become failures', () async {
      for (final (status, code, failure) in [
        (429, 'quota_exhausted', TutorFailure.quota),
        (503, 'llm_unavailable', TutorFailure.unavailable),
        (502, 'llm_refused', TutorFailure.refused),
        (502, 'llm_failed', TutorFailure.failed),
        (400, 'bad_json', TutorFailure.invalid),
        (400, 'invalid_input', TutorFailure.invalid),
        (400, 'missing_response', TutorFailure.invalid),
        (400, 'unsupported_pair', TutorFailure.invalid),
        (401, 'unauthorized', TutorFailure.unknown),
      ]) {
        final repository = repositoryWith(
          (sent) async => json(sent, status, {
            'error': {'code': code},
          }),
        );
        final result = await repository.answerCheck(request);
        expect((result as Err).error, failure, reason: code);
      }
    });

    test('no connection, or no answer in time, is a network failure', () async {
      for (final error in [
        ClientException('offline'),
        RequestAbortedException(),
      ]) {
        final repository = repositoryWith((sent) async => throw error);
        expect(
          (await repository.answerCheck(request) as Err).error,
          TutorFailure.network,
          reason: '$error',
        );
      }
    });

    test('the request is cut off after the wait', () async {
      final repository = SupabaseTutorRepository(
        SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test',
          httpClient: _NeverAnswers(),
        ),
        wait: Duration.zero,
      );
      expect(
        (await repository.answerCheck(request) as Err).error,
        TutorFailure.network,
      );
    });

    test('an answer off the contract is invalid', () async {
      for (final body in <Object?>[
        {...answer, 'verdict': 'maybe'},
        {...answer, 'ladder': null},
        {...answer, 'confidence': 'high'},
        'not an object',
      ]) {
        final repository = repositoryWith(
          (sent) async => json(sent, 200, body),
        );
        expect(
          (await repository.answerCheck(request) as Err).error,
          TutorFailure.invalid,
          reason: '$body',
        );
      }
      final broken = repositoryWith(
        (sent) async => Response(
          '{"verdict":',
          200,
          headers: {'content-type': 'application/json'},
          request: sent,
        ),
      );
      expect(
        (await broken.answerCheck(request) as Err).error,
        TutorFailure.invalid,
      );
    });

    test('an answer without a code is an unknown failure', () {
      expect(tutorFailure('Bad Gateway'), TutorFailure.unknown);
      expect(tutorFailure(const {'error': 'x'}), TutorFailure.unknown);
    });
  });
}

/// A server that never answers: only the abort signal ends the request.
class _NeverAnswers extends BaseClient {
  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final abort = (request as Abortable).abortTrigger!;
    await abort;
    throw RequestAbortedException(request.url);
  }
}

void gapSuggestTests() {
  const gapRequest = GapSuggestRequest(
    l1: 'tr',
    l2: 'en',
    level: CefrLevel.a1,
    explainInL1: true,
    l1Text: 'canım sıkıldı',
    context: GapContext.pair,
    note: 'akşam',
  );
  const suggestion = <String, Object?>{
    'l2_natural': "Let's go out, I'm bored.",
    'l2_simple': 'I am bored. We can go out.',
    'key_chunk': {'text': 'go out', 'gloss_l1': 'dışarı çıkmak'},
    'register': 'informal',
    'notes_l1': null,
    'above_level': <String>[],
    'simplified': false,
    'provider': 'gemini',
    'model': 'gemini-3.5-flash',
  };

  group('gap_suggest (docs/07-ai-tutor.md §4.3)', () {
    test('sends what could not be said and reads the suggestion', () async {
      late Request seen;
      final repository = repositoryWith((sent) async {
        seen = sent;
        return json(sent, 200, suggestion);
      });
      final result = await repository.gapSuggest(gapRequest);
      final value = (result as Ok<GapSuggestion, TutorFailure>).value;
      expect(value.l2Simple, 'I am bored. We can go out.');
      expect(
        value.keyChunk,
        const KeyChunk(text: 'go out', glossL1: 'dışarı çıkmak'),
      );
      expect(value.notesL1, isNull);
      expect(seen.url.path, '/functions/v1/tutor/gap_suggest');
      expect(jsonDecode(seen.body), {
        'ctx': {'l1': 'tr', 'l2': 'en', 'level': 'A1', 'explain_in': 'l1'},
        'l1_text': 'canım sıkıldı',
        'context': 'pair',
        'note': 'akşam',
      });
    });

    test('its codes are failures too', () async {
      for (final (code, failure) in [
        ('missing_text', TutorFailure.invalid),
        ('quota_exhausted', TutorFailure.quota),
      ]) {
        final repository = repositoryWith(
          (sent) async => json(sent, 400, {
            'error': {'code': code},
          }),
        );
        expect((await repository.gapSuggest(gapRequest) as Err).error, failure);
      }
      final broken = repositoryWith(
        (sent) async => json(sent, 200, {...suggestion, 'key_chunk': 'x'}),
      );
      expect(
        (await broken.gapSuggest(gapRequest) as Err).error,
        TutorFailure.invalid,
      );
    });
  });
}

void speakingAnnotateTests() {
  const annotateRequest = SpeakingAnnotateRequest(
    l1: 'tr',
    l2: 'en',
    level: CefrLevel.a1,
    explainInL1: true,
    prompt: 'Evini anlat.',
    goal: 'Describe your home.',
    canDoCodes: ['cd.describe_experience.a1'],
    words: [
      TimedWord(text: 'my', startMs: 0, endMs: 200),
      TimedWord(text: 'home', startMs: 300, endMs: 600),
    ],
  );
  const marks = <String, Object?>{
    'clauses': [
      {'start_i': 0, 'end_i': 1, 'as_unit': 0, 'error_free': true},
    ],
    'errors': <Object?>[],
    'fillers': <Object?>[],
    'repairs': <Object?>[],
    'structures_used': <Object?>[],
    'task_outcome': 'not_done',
    'strengths': <Object?>[],
    'corrections': <Object?>[],
    'catalog': 'tr-en@1',
    'prompt_version': 'speaking_annotate@1',
    'provider': 'gemini',
    'model': 'gemini-3.5-flash',
  };

  group('speaking_annotate (docs/07-ai-tutor.md §4.2)', () {
    test(
      'sends the transcript and reads the marks with their source',
      () async {
        late Request seen;
        final repository = repositoryWith((sent) async {
          seen = sent;
          return json(sent, 200, marks);
        });
        final result = await repository.speakingAnnotate(annotateRequest);
        final value = (result as Ok<AnnotatedSpeech, TutorFailure>).value;
        expect(value.annotation.taskOutcome, TaskOutcome.notDone);
        expect(value.annotation.clauses.single.errorFree, isTrue);
        expect(value.catalog, 'tr-en@1');
        expect(value.promptVersion, 'speaking_annotate@1');
        expect(value.toJson()['model'], 'gemini-3.5-flash');
        expect(seen.url.path, '/functions/v1/tutor/speaking_annotate');
        expect(jsonDecode(seen.body), {
          'ctx': {'l1': 'tr', 'l2': 'en', 'level': 'A1', 'explain_in': 'l1'},
          'task': {
            'prompt_l1': 'Evini anlat.',
            'goal': 'Describe your home.',
            'can_do_codes': ['cd.describe_experience.a1'],
          },
          'words': [
            {'i': 0, 'w': 'my', 'start_ms': 0, 'end_ms': 200},
            {'i': 1, 'w': 'home', 'start_ms': 300, 'end_ms': 600},
          ],
          'assessment': false,
        });
      },
    );

    test(
      'its codes are failures; marks off the contract are invalid',
      () async {
        final unavailable = repositoryWith(
          (sent) async => json(sent, 503, {
            'error': {'code': 'llm_unavailable'},
          }),
        );
        expect(
          (await unavailable.speakingAnnotate(annotateRequest) as Err).error,
          TutorFailure.unavailable,
        );
        for (final broken in [
          {...marks, 'task_outcome': 'maybe'},
          {...marks, 'catalog': 3},
        ]) {
          final repository = repositoryWith(
            (sent) async => json(sent, 200, broken),
          );
          expect(
            (await repository.speakingAnnotate(annotateRequest) as Err).error,
            TutorFailure.invalid,
          );
        }
      },
    );
  });
}
