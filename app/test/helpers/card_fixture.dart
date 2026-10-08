import 'dart:typed_data';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/card_content_repository.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/data/tasks/recording_files.dart';
import 'package:dilbaz_app/data/tasks/recording_store.dart';
import 'package:dilbaz_app/data/tasks/task_content_repository.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/data/tutor/annotated_speech.dart';
import 'package:dilbaz_app/data/tutor/answer_check_request.dart';
import 'package:dilbaz_app/data/tutor/gap_suggest_request.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:dilbaz_app/data/tutor/speaking_annotate_request.dart';
import 'package:dilbaz_app/data/tutor/tutor_providers.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show Value;
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

/// Speaking tasks of the synthetic language: an anchor of the monthly
/// test, an A1 task and an A2 task.
const anchorTask = 'zz.task.anc_1';
const homeTask = 'zz.task.home';
const cityTask = 'zz.task.city';

/// Packs of the synthetic language for card sessions: two words with a
/// carrier each and a chunk. For a learner at A2 the curriculum takes
/// bada, then sima, then the chunk (it is C1). The packs also hold three
/// speaking tasks and the connectors.
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
        'connectors': [
          {'text': 'kolu', 'level': 'A1'},
        ],
        'can_dos': [
          {'code': 'cd.zz.A1', 'level': 'A1', 'scale': 'describing'},
          {'code': 'cd.zz.A2', 'level': 'A2', 'scale': 'describing'},
        ],
      },
      tasks: [
        for (final (key, level, anchor, phrases) in [
          (anchorTask, 'A1', 'ANC-1', <String>[]),
          (homeTask, 'A1', null, ['Bada ...', 'Sima ...', 'Kolu ...']),
          (cityTask, 'A2', null, ['Dero ...', 'Bada ...', 'Sima ...']),
        ])
          ContentTasksCompanion.insert(
            key: key,
            packId: target,
            kind: 'speaking',
            level: level,
            data: Value({
              'anchor': anchor,
              'can_do': ['cd.zz.$level'],
              'goal': 'Talk about $key.',
              'phrases': phrases,
            }),
          ),
      ],
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
        for (final (key, title) in [
          (anchorTask, 'Kendini tanıt'),
          (homeTask, 'Evin'),
          (cityTask, 'Şehrin'),
        ])
          ContentPairEntriesCompanion.insert(
            kind: 'task_instruction',
            key: key,
            packId: pair,
            data: {
              'title': title,
              'prompt': '$title: anlat.',
              'phrases': [
                if (key != anchorTask) ...['Bada demek', 'Sima demek', 'Kolu'],
              ],
            },
          ),
        for (final (code, summary) in [
          ('cd.zz.A1', 'Kendini anlatabilirsin.'),
          ('cd.zz.A2', 'Şehrini anlatabilirsin.'),
        ])
          ContentPairEntriesCompanion.insert(
            kind: 'can_do_summary',
            key: code,
            packId: pair,
            data: {'summary': summary},
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

  /// The next suggestion; null makes [gapSuggest] fail with [gapFailure].
  GapSuggestion? suggestion = gapSuggestion();
  TutorFailure gapFailure = TutorFailure.quota;
  final gapAsked = <GapSuggestRequest>[];

  @override
  Future<Result<GapSuggestion, TutorFailure>> gapSuggest(
    GapSuggestRequest request,
  ) async {
    gapAsked.add(request);
    final suggestion = this.suggestion;
    return suggestion == null ? Err(gapFailure) : Ok(suggestion);
  }

  /// The next marks; null makes [speakingAnnotate] fail with
  /// [annotateFailure].
  AnnotatedSpeech? annotated;
  TutorFailure annotateFailure = TutorFailure.unavailable;
  final annotateAsked = <SpeakingAnnotateRequest>[];

  @override
  Future<Result<AnnotatedSpeech, TutorFailure>> speakingAnnotate(
    SpeakingAnnotateRequest request,
  ) async {
    annotateAsked.add(request);
    final annotated = this.annotated;
    return annotated == null ? Err(annotateFailure) : Ok(annotated);
  }
}

/// A suggestion of `gap_suggest`.
GapSuggestion gapSuggestion({
  String natural = "Let's go out, I'm bored.",
  String simple = 'I am bored. We can go out.',
  String? notes = "'bored' sıkılmış demektir.",
}) => GapSuggestion(
  l2Natural: natural,
  l2Simple: simple,
  keyChunk: const KeyChunk(text: 'go out', glossL1: 'dışarı çıkmak'),
  register: 'informal',
  notesL1: notes,
  provider: 'fake',
  model: 'fake-model',
);

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
  appDatabaseProvider.overrideWithValue(db),
  ...cardDataOverrides(db: db, tutor: tutor, clock: clock),
];

/// The card session's own data, on top of the app's fakes and its
/// database [db] (pass it to `pumpDilbazApp` too): the packs of
/// [installCardPacks] read as `zz`, the tutor, a fixed clock and seed.
List<Override> cardDataOverrides({
  required AppDatabase db,
  required FakeTutorRepository tutor,
  DateTime Function()? clock,
  FakeAudioRemote? audio,
}) => [
  cardContentRepositoryProvider.overrideWith(
    (ref) => DriftCardContentRepository(db, l2: 'zz'),
  ),
  taskContentRepositoryProvider.overrideWith(
    (ref) => DriftTaskContentRepository(db, l2: 'zz'),
  ),
  recordingStoreProvider.overrideWithValue(FakeRecordingStore()),
  audioRemoteProvider.overrideWithValue(audio ?? FakeAudioRemote()),
  tutorRepositoryProvider.overrideWithValue(tutor),
  clockProvider.overrideWithValue(clock ?? () => cardNow),
  cardSeedProvider.overrideWithValue(1),
];

/// The private audio bucket in memory.
class FakeAudioRemote implements AudioRemote {
  final files = <String, Uint8List>{};

  /// Why the next calls fail; null means they work.
  AudioFailure? failure;

  @override
  Future<Result<void, AudioFailure>> upload(
    String path,
    Uint8List bytes,
  ) async {
    final failure = this.failure;
    if (failure != null) return Err(failure);
    files[path] = bytes;
    return const Ok(null);
  }

  @override
  Future<Result<Uint8List, AudioFailure>> download(String path) async {
    final failure = this.failure;
    if (failure != null) return Err(failure);
    final bytes = files[path];
    return bytes == null ? const Err(AudioFailure.refused) : Ok(bytes);
  }
}

/// Recordings kept in memory.
class FakeRecordingStore implements RecordingStore {
  final files = <String, Uint8List>{};

  @override
  Future<String?> save(String id, RecordedAudio audio) async {
    final path = '/recordings/$id.${recordingExtension(audio.contentType)}';
    files[path] = audio.bytes;
    return path;
  }

  @override
  Future<Uint8List?> read(String path) async => files[path];

  @override
  Future<void> delete(String path) async => files.remove(path);

  @override
  Future<String?> find(String audioPath) async {
    final here = '/recordings/${audioPath.split('/').last}';
    for (final path in [audioPath, here]) {
      if (files.containsKey(path)) return path;
    }
    return null;
  }

  @override
  Future<String?> keepFetched(String audioPath, Uint8List bytes) async {
    final here = '/recordings/${audioPath.split('/').last}';
    files[here] = bytes;
    return here;
  }
}
