import 'dart:convert';
import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final RecordedAudio audio = (
  bytes: Uint8List.fromList([1, 2, 3, 4]),
  contentType: 'audio/mp4',
  duration: const Duration(seconds: 3),
);

SupabaseSpeechRepository repositoryWith(MockClientHandler handler) =>
    SupabaseSpeechRepository(
      SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test',
        httpClient: MockClient(handler),
      ),
    );

Response error(Request request, int status, String code) => Response(
  jsonEncode({
    'error': {'code': code},
  }),
  status,
  headers: {'content-type': 'application/json'},
  request: request,
);

void main() {
  group('SupabaseSpeechRepository (docs/08-speech.md §5.1)', () {
    test('sends the audio as it is and reads the transcript', () async {
      late Request seen;
      final repository = repositoryWith((request) async {
        seen = request;
        return Response(
          jsonEncode({
            'text': 'uh he go to work',
            'words': [
              {'w': 'uh', 'startMs': 80, 'endMs': 200, 'conf': 0.9},
            ],
            'provider': 'deepgram',
            'model': 'nova-3',
            'durationMs': 3000,
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });

      final result = await repository.transcribe(audio);

      expect(
        (result as Ok<Transcript, SpeechFailure>).value,
        const Transcript(
          text: 'uh he go to work',
          words: [TranscriptWord(w: 'uh', startMs: 80, endMs: 200, conf: 0.9)],
          provider: 'deepgram',
          model: 'nova-3',
          durationMs: 3000,
        ),
      );
      expect(seen.url.path, '/functions/v1/speech/transcribe');
      expect(seen.url.queryParameters, {'lang': 'en'});
      expect(seen.headers['Content-Type'], 'audio/mp4');
      expect(seen.bodyBytes, [1, 2, 3, 4]);
    });

    test('the codes of the function become calm failures', () async {
      for (final (status, code, failure) in [
        (503, 'stt_unavailable', SpeechFailure.unavailable),
        (400, 'unsupported_language', SpeechFailure.unavailable),
        (503, 'stt_quota', SpeechFailure.quota),
        (503, 'stt_busy', SpeechFailure.busy),
        (502, 'stt_failed', SpeechFailure.busy),
        (422, 'bad_audio', SpeechFailure.badAudio),
        (413, 'audio_too_large', SpeechFailure.badAudio),
        (415, 'unsupported_audio', SpeechFailure.badAudio),
        (400, 'empty_audio', SpeechFailure.badAudio),
        (500, 'something_else', SpeechFailure.unknown),
      ]) {
        final repository = repositoryWith(
          (request) async => error(request, status, code),
        );
        final result = await repository.transcribe(audio);
        expect((result as Err).error, failure, reason: code);
      }
    });

    test('no connection is a network failure', () async {
      final repository = repositoryWith(
        (request) async => throw ClientException('offline'),
      );
      expect(
        (await repository.transcribe(audio) as Err).error,
        SpeechFailure.network,
      );
    });

    test('an answer without a code is an unknown failure', () {
      expect(speechFailure('Bad Gateway'), SpeechFailure.unknown);
      expect(speechFailure(const {'error': 'x'}), SpeechFailure.unknown);
    });
  });
}
