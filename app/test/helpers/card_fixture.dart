import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/card_content_repository.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/data/tutor/answer_check_request.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:dilbaz_app/data/tutor/tutor_providers.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/cards/application/card_session_controller.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';
import 'fake_profile_repository.dart';
import 'fake_speech.dart';
import 'pack_fixture.dart';
import 'placement_fixture.dart';

/// The time the card tests run at: mid-morning, far from midnight
/// anywhere the tests run.
final DateTime cardNow = DateTime.utc(2026, 10, 1, 9);

/// Keys of the card fixture.
const bada = 'zz.ws.bada.n.1';
const sima = 'zz.ws.sima.n.1';
const deroKolu = 'zz.chunk.dero_kolu';
const badaSentence = 'zz.sent.0001';

/// Packs of the synthetic language for card sessions: two words with a
/// carrier each and a chunk. For a learner at A2 the curriculum takes
/// bada, then sima, then the chunk (it is C1).
Future<void> installCardPacks(AppDatabase db) async {
  const target = 'zz@1';
  const pair = 'qq-zz@1';
  final packs = [
    await buildPack(
      id: target,
      kind: 'target',
      manifest: {
        'min_engine_version': 1,
        'script': {'direction': 'ltr', 'word_separator': 'space'},
      },
      meta: {
        'audio': {'prefix': 'zz/'},
      },
      normalization: soundNormalization,
      items: [
        item(
          bada,
          'word_sense',
          packId: target,
          text: 'bada',
          lemmas: ['bada'],
          rank: 10,
          data: {
            'carriers': [badaSentence],
          },
        ),
        item(
          sima,
          'word_sense',
          packId: target,
          text: 'sima',
          lemmas: ['sima'],
          rank: 20,
          data: {
            'carriers': ['zz.sent.0002'],
          },
        ),
        item(
          deroKolu,
          'chunk',
          packId: target,
          level: 'C1',
          text: 'Dero kolu.',
          lemmas: ['dero', 'kolu'],
        ),
        item(
          badaSentence,
          'sentence',
          packId: target,
          text: 'Bada kolu.',
          lemmas: ['bada', 'kolu'],
          targets: [bada],
          data: {
            'audio': [
              {'voice': 'v1', 'speed': 1.0, 'file': 'v1/0001.mp3'},
              {'voice': 'v1', 'speed': 0.8, 'file': 'v1/0001s.mp3'},
            ],
          },
        ),
        item(
          'zz.sent.0002',
          'sentence',
          packId: target,
          text: 'Sima dero.',
          lemmas: ['sima', 'dero'],
          targets: [sima],
        ),
      ],
      forms: [
        for (final (form, lemma) in [
          ('bada', 'bada'),
          ('badan', 'bada'),
          ('kolu', 'kolu'),
          ('sima', 'sima'),
          ('dero', 'dero'),
        ])
          ContentFormsCompanion.insert(
            form: form,
            lemma: lemma,
            packId: target,
          ),
      ],
    ),
    await buildPack(
      id: pair,
      kind: 'pair',
      l1: 'qq',
      pairEntries: [
        for (final (key, data) in [
          (bada, {'meaning': 'bada demek', 'usage_note': 'hep böyle'}),
          (sima, {'meaning': 'sima demek'}),
          (deroKolu, {'meaning': 'Dero kolu de.'}),
          (
            badaSentence,
            {'meaning': 'Bada kolu diye sor.', 'context': 'dosta'},
          ),
          ('zz.sent.0002', {'meaning': 'Sima dero de.'}),
        ])
          ContentPairEntriesCompanion.insert(
            kind: 'gloss',
            key: key,
            packId: pair,
            data: data,
          ),
        ContentPairEntriesCompanion.insert(
          kind: 'variants',
          key: badaSentence,
          packId: pair,
          data: const {
            'variants': ['Kolu bada.'],
            'alternatives': ['Sima kolu.'],
          },
        ),
      ],
    ),
  ];
  for (final built in packs) {
    final result = await PackImporter(db).import(built.bytes, built.info);
    expect(result, isA<Ok<void, PackFailure>>(), reason: built.info.id);
  }
}

/// What the fake tutor answers.
LlmAnswerCheck llmCheck(
  Verdict verdict, {
  bool? targetOk,
  List<String> tags = const [],
  List<ErrorSpan> spans = const [],
  LlmLadder ladder = const LlmLadder(h1: '', h2: '', h3: '', h4: ''),
  String? variantToLearn,
}) => LlmAnswerCheck(
  verdict: verdict,
  targetOk: targetOk ?? verdict == Verdict.correct,
  errorTags: tags,
  errorSpans: spans,
  ladder: ladder,
  confidence: 0.9,
  catalog: 'qq-zz@1',
  provider: 'fake',
  model: 'fake-model',
  variantToLearn: variantToLearn,
);

/// A tutor that answers as told, or fails as told.
class FakeTutorRepository implements TutorRepository {
  /// The next answers, in order; when none is left, [failure] or an
  /// uncertain verdict.
  final answers = <LlmAnswerCheck>[];

  /// Why the tutor fails once [answers] is empty; null for uncertain.
  TutorFailure? failure;
  final asked = <AnswerCheckRequest>[];

  @override
  Future<Result<LlmAnswerCheck, TutorFailure>> answerCheck(
    AnswerCheckRequest request,
  ) async {
    asked.add(request);
    if (answers.isNotEmpty) return Ok(answers.removeAt(0));
    final failure = this.failure;
    return failure != null
        ? Err(failure)
        : Ok(llmCheck(Verdict.uncertain, targetOk: false));
  }
}

/// Everything a card session reaches outside itself, on [db] with the
/// packs of [installCardPacks].
List<Override> cardSessionOverrides({
  required AppDatabase db,
  required FakeProfileRepository profiles,
  required FakeTutorRepository tutor,
  required FakeSpeechRepository speech,
  required FakeAnswerRecorder recorder,
  required FakePackAudio audio,
  required FakeClipPlayer player,
  FakeAssessmentRepository? assessments,
  DateTime Function()? clock,
}) => [
  authRepositoryProvider.overrideWithValue(FakeAuthRepository(signedIn: true)),
  profileRepositoryProvider.overrideWithValue(profiles),
  assessmentRepositoryProvider.overrideWithValue(
    assessments ?? FakeAssessmentRepository(open: false),
  ),
  speechRepositoryProvider.overrideWithValue(speech),
  answerRecorderProvider.overrideWithValue(recorder),
  packAudioProvider.overrideWithValue(audio),
  clipPlayerProvider.overrideWithValue(player),
  ...cardDataOverrides(db: db, tutor: tutor, clock: clock),
];

/// The card session's own data, on top of the app's fakes: [db] with the
/// packs of [installCardPacks], the tutor, a fixed clock and seed.
List<Override> cardDataOverrides({
  required AppDatabase db,
  required FakeTutorRepository tutor,
  DateTime Function()? clock,
}) => [
  appDatabaseProvider.overrideWithValue(db),
  cardContentRepositoryProvider.overrideWith(
    (ref) => DriftCardContentRepository(db, l2: 'zz'),
  ),
  tutorRepositoryProvider.overrideWithValue(tutor),
  clockProvider.overrideWithValue(clock ?? () => cardNow),
  cardSeedProvider.overrideWithValue(1),
];
