import 'dart:io';
import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/tutor/gap_suggest_request.dart';
import 'package:dilbaz_app/data/tutor/speaking_annotate_request.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/speaking/application/recording_pipeline.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The folder of the live check (docs/15-testing.md §4a): `live.env` with
/// the local stack's URL and anon key and a local test learner's e-mail
/// and password (`make_live_user.py`), and the recordings `live_en.wav`
/// and `live_tr.wav` (`make_live_audio.ps1`).
const _folder = String.fromEnvironment('DILBAZ_LIVE');

/// The speech and tutor routes as the app calls them: its own clients
/// against a local Supabase stack whose functions call the real providers
/// (Deepgram, Groq, Gemini). It spends a few free-quota calls, so it runs
/// only by hand:
///
///     flutter test test_live --dart-define=DILBAZ_LIVE=<folder>
void main() {
  final skip = _folder.isEmpty
      ? 'Live check: run by hand with --dart-define=DILBAZ_LIVE=<folder>'
      : null;
  late SupabaseClient client;
  late SupabaseSpeechRepository speech;
  late SupabaseTutorRepository tutor;
  var spoken = <TimedWord>[];

  setUpAll(() async {
    if (skip != null) return;
    final env = {
      for (final line in File('$_folder/live.env').readAsLinesSync())
        if (line.split('=') case [final key, ...final value])
          key: value.join('='),
    };
    client = SupabaseClient(
      env['DILBAZ_LIVE_URL']!,
      env['DILBAZ_LIVE_ANON']!,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    await client.auth.signInWithPassword(
      email: env['DILBAZ_LIVE_EMAIL'],
      password: env['DILBAZ_LIVE_PASSWORD']!,
    );
    speech = SupabaseSpeechRepository(client);
    tutor = SupabaseTutorRepository(client);
  });

  tearDownAll(() async {
    if (skip == null) await client.dispose();
  });

  /// A 16-bit mono WAV of the folder; its length from the header.
  RecordedAudio wav(String name) {
    final bytes = File('$_folder/$name').readAsBytesSync();
    final byteRate = ByteData.sublistView(
      bytes,
      28,
      32,
    ).getUint32(0, Endian.little);
    return (
      bytes: bytes,
      contentType: 'audio/wav',
      duration: Duration(milliseconds: (bytes.length - 44) * 1000 ~/ byteRate),
    );
  }

  test('English speech is written down word by word', () async {
    final transcript = switch (await speech.transcribe(wav('live_en.wav'))) {
      Ok(:final value) => value,
      Err(:final error) => fail('transcribe: $error'),
    };
    spoken = timedWords(transcript);
    stdout.writeln(
      'en: ${transcript.provider}/${transcript.model}, '
      '${spoken.length} words: ${transcript.text}',
    );
    expect(spoken.length, greaterThan(40));
    // Verbatim: the learner's slip stays (docs/08-speech.md §3).
    expect(transcript.text.toLowerCase(), contains('i am work'));
  }, skip: skip);

  test('the tutor marks a speaking task', () async {
    final watch = Stopwatch()..start();
    final marked = await tutor.speakingAnnotate(
      SpeakingAnnotateRequest(
        l1: 'tr',
        l2: 'en',
        level: CefrLevel.a2,
        explainInL1: true,
        prompt:
            'Kendini tanıt: kim olduğunu, ne iş yaptığını, nerede '
            'yaşadığını ve neleri sevdiğini anlat.',
        goal:
            'Introduce yourself: who you are, what you do, where you '
            'live and what you like.',
        words: spoken,
      ),
    );
    final annotated = switch (marked) {
      Ok(:final value) => value,
      Err(:final error) => fail('speaking_annotate: $error'),
    };
    final annotation = annotated.annotation;
    final corrections = [
      for (final c in annotation.corrections) '${c.original} → ${c.corrected}',
    ];
    stdout.writeln(
      'annotate: ${annotated.provider}/${annotated.model} in '
      '${watch.elapsed.inSeconds} s; ${annotation.clauses.length} clauses, '
      '${annotation.clauses.where((c) => c.errorFree).length} error-free; '
      'corrections: $corrections',
    );
    expect(annotation.clauses, isNotEmpty);
    expect(annotation.errors, isNotEmpty);
    expect(annotation.corrections, isNotEmpty);
  }, skip: skip);

  test('Turkish speech is written down on the server', () async {
    final transcript = switch (await speech.transcribe(
      wav('live_tr.wav'),
      lang: 'tr',
    )) {
      Ok(:final value) => value,
      Err(:final error) => fail('transcribe tr: $error'),
    };
    stdout.writeln(
      'tr: ${transcript.provider}/${transcript.model}: ${transcript.text}',
    );
    expect(transcript.text.toLowerCase(), contains('dışarı'));
  }, skip: skip);

  test('the tutor suggests the English for what could not be said', () async {
    final watch = Stopwatch()..start();
    final suggestion = switch (await tutor.gapSuggest(
      const GapSuggestRequest(
        l1: 'tr',
        l2: 'en',
        level: CefrLevel.a2,
        explainInL1: true,
        l1Text: 'Canım sıkıldı, hadi dışarı çıkalım.',
        context: GapContext.daily,
      ),
    )) {
      Ok(:final value) => value,
      Err(:final error) => fail('gap_suggest: $error'),
    };
    stdout.writeln(
      'gap: ${suggestion.provider}/${suggestion.model} in '
      '${watch.elapsed.inSeconds} s: "${suggestion.l2Natural}" / '
      '"${suggestion.l2Simple}", chunk "${suggestion.keyChunk.text}"',
    );
    expect(suggestion.l2Natural, isNotEmpty);
    expect(suggestion.keyChunk.text, isNotEmpty);
  }, skip: skip);
}
