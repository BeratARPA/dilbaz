import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/data/tutor/pron_check.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/shadowing/application/shadowing_controller.dart';
import 'package:dilbaz_app/features/shadowing/application/shadowing_state.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../dictation_practice/dictation_practice_controller_test.dart'
    show understood;

/// What `pron_check` hears: [issues] as (index, word, tag).
HeardPronunciation heardAs(
  List<(int, String, String)> issues, {
  bool uncertain = false,
}) => HeardPronunciation(
  uncertain: uncertain,
  issues: [
    for (final (index, word, tag) in issues)
      (index: index, word: word, tag: tag, heard: '${word}x'),
  ],
  catalog: 'qq-zz@1',
  promptVersion: 'pron_check@1',
  provider: 'gemini',
  model: 'm',
);

void main() {
  late AppDatabase db;
  late FakeAssessmentRepository assessments;
  late FakeProfileRepository profiles;
  late FakeTutorRepository tutor;
  late FakeSpeechRepository speech;
  late FakeAnswerRecorder recorder;
  late FakePackAudio audio;
  late FakeClipPlayer player;
  late ProviderContainer container;
  var made = false;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
    assessments = FakeAssessmentRepository(open: false);
    profiles = FakeProfileRepository(onboarded: true);
    tutor = FakeTutorRepository();
    speech = FakeSpeechRepository(heard: 'bada kolu');
    recorder = FakeAnswerRecorder();
    audio = FakePackAudio();
    player = FakeClipPlayer();
    made = false;
  });

  tearDown(() async {
    if (made) container.dispose();
    await db.close();
  });

  ShadowingController controller() =>
      container.read(shadowingControllerProvider.notifier);
  ShadowingState? current() =>
      container.read(shadowingControllerProvider).value;

  Future<ShadowingState> start() async {
    container = ProviderContainer(
      overrides: cardSessionOverrides(
        db: db,
        profiles: profiles,
        tutor: tutor,
        speech: speech,
        recorder: recorder,
        audio: audio,
        player: player,
        assessments: assessments,
      ),
    )..listen(shadowingControllerProvider, (_, _) {});
    made = true;
    return await container.read(shadowingControllerProvider.future);
  }

  Future<List<AttemptRow>> attempts() => (db.select(
    db.attempts,
  )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get();

  /// Hears the sentence and says it.
  Future<void> say() async {
    await controller().listen();
    await controller().record();
    await controller().stop();
  }

  test('without audio consent, or a sentence to follow, nothing', () async {
    profiles.audioConsent = false;
    expect(await start(), const ShadowingState.needsConsent());
    container.dispose();
    profiles.audioConsent = true;
    expect(await start(), const ShadowingState.nothingToSay());
  });

  test('heard, said, recognized and heard: the most severe first, at most '
      'two', () async {
    await understood(db, assessments);
    tutor.heard = heardAs([
      (0, 'Bada', 'zz.phon.b'),
      (1, 'kolu', 'zz.phon.a'),
      (1, 'kolu', 'zz.gram.c'),
    ]);
    speech.heard = 'bada sima';
    final first = await start() as ShadowingSentence;
    expect(first.text, 'Bada kolu.');
    // Nothing to say before the sentence is heard.
    await controller().record();
    expect(recorder.starts, 0);

    await say();
    expect(recorder.pronunciation, isTrue);
    expect(player.played, ['/clips/zz/v1/0001.mp3']);
    final request = tutor.pronAsked.single;
    expect(request.reference, 'Bada kolu.');
    expect(request.level, CefrLevel.a2);
    final result = current()! as ShadowingResult;
    expect(result.words, ['bada', 'kolu']);
    expect(result.marks, [DictationMark.heard, DictationMark.changed]);
    expect(result.issues.map((i) => (i.word, i.tag, i.about)), [
      ('kolu', 'zz.phon.a', 'A sesi kısa kalmış.'),
      ('Bada', 'zz.phon.b', 'B sesi yumuşamış.'),
    ]);
    expect(result.judgement, PronJudgement.heard);
    expect(result.canTryAgain, isTrue);
    expect(result.canHearSelf, isTrue);

    final stored = (await attempts()).single;
    expect(stored.activity, 'shadowing');
    expect(stored.itemRef, badaSentence);
    // Every tag of the catalog heard, shown or not; never one outside.
    expect(stored.errorTags, ['zz.phon.b', 'zz.phon.a']);
    expect(stored.llm?['prompt_version'], 'pron_check@1');
    expect(stored.response['text'], 'bada sima');
  });

  test('the own try is heard next to the model, then removed', () async {
    await understood(db, assessments);
    tutor.heard = heardAs(const []);
    await start();
    await say();
    final store = container.read(recordingStoreProvider) as FakeRecordingStore;
    expect(store.files.keys, ['/recordings/shadowing_try.wav']);
    await controller().hearSelf();
    await controller().hearModel();
    expect(player.played.skip(1), [
      '/recordings/shadowing_try.wav',
      '/clips/zz/v1/0001.mp3',
    ]);
    final result = current()! as ShadowingResult;
    expect(result.playing, isFalse);
    // Every word recognized and nothing heard: no second try is offered.
    expect(result.issues, isEmpty);
    expect(result.canTryAgain, isFalse);
    await controller().next();
    expect(store.files, isEmpty);
    expect(
      current(),
      const ShadowingState.done(sentences: 1, shown: {}, about: {}),
    );
    final session = (await db.select(db.sessions).get()).single;
    expect(session.strandMs.keys, ['fluency']);
    expect(session.planned, {'activity': 'shadowing'});
  });

  test(
    'a second try follows the first; what was shown is counted once',
    () async {
      await understood(db, assessments);
      tutor.heard = heardAs([(1, 'kolu', 'zz.phon.a')]);
      await start();
      await say();
      await controller().tryAgain();
      final again = current()! as ShadowingSentence;
      expect(again.again, isTrue);
      expect(again.heard, isTrue, reason: 'the sentence was heard already');
      await controller().record();
      await controller().stop();
      expect((current()! as ShadowingResult).canTryAgain, isFalse);
      await controller().next();
      final stored = await attempts();
      expect(stored.last.parentAttemptId, stored.first.id);
      final done = current()! as ShadowingDone;
      expect(done.shown, {'zz.phon.a': 1});
      expect(done.about, {'zz.phon.a': 'A sesi kısa kalmış.'});
    },
  );

  test('not heard, unsure, or not recognized: what remains is said', () async {
    await understood(db, assessments);
    tutor.pronFailure = TutorFailure.unavailable;
    speech.heard = 'bada';
    await start();
    await say();
    var result = current()! as ShadowingResult;
    expect(result.judgement, PronJudgement.notHeard);
    expect(result.issues, isEmpty);
    // A word not recognized still offers a second try.
    expect(result.marks, [DictationMark.heard, DictationMark.missed]);
    expect(result.canTryAgain, isTrue);
    container.dispose();

    tutor.heard = heardAs([(1, 'kolu', 'zz.phon.a')], uncertain: true);
    speech.failure = SpeechFailure.network;
    await start();
    await say();
    result = current()! as ShadowingResult;
    expect(result.judgement, PronJudgement.uncertain);
    expect(result.marks, isNull);
    expect(result.words, ['Bada', 'kolu.']);
    expect(result.issues, isEmpty);
    expect((await attempts()).last.errorTags, isEmpty);
  });

  test('a silent or failed recording asks for the sentence again', () async {
    await understood(db, assessments);
    tutor.heard = heardAs(const []);
    await start();
    await controller().listen();

    recorder.failure = RecordFailure.permission;
    await controller().record();
    expect(
      (current()! as ShadowingSentence).failure,
      SpeakingFailure.permission,
    );
    recorder.failure = RecordFailure.device;
    await controller().record();
    expect(
      (current()! as ShadowingSentence).failure,
      SpeakingFailure.microphone,
    );
    recorder
      ..failure = null
      ..silent = true;
    await controller().record();
    await controller().stop();
    expect((current()! as ShadowingSentence).failure, SpeakingFailure.silent);
    recorder.silent = false;

    speech.heard = '';
    await controller().record();
    await controller().stop();
    expect((current()! as ShadowingSentence).failure, SpeakingFailure.silent);
    expect(await attempts(), isEmpty);
  });

  test(
    'a clip that cannot be had says so; leaving keeps what was said',
    () async {
      await understood(db, assessments);
      tutor.heard = heardAs(const []);
      await start();
      audio.failure = PackFailure.network;
      await controller().listen();
      expect(
        (current()! as ShadowingSentence).audioFailure,
        PackFailure.network,
      );
      audio.failure = null;
      await say();
      await controller().leave();
      await controller().leave();
      expect(await attempts(), hasLength(1));
      expect(await db.select(db.sessions).get(), hasLength(1));
      final store =
          container.read(recordingStoreProvider) as FakeRecordingStore;
      expect(store.files, isEmpty);
    },
  );

  test('leaving while recording throws the recording away', () async {
    await understood(db, assessments);
    await start();
    await controller().listen();
    await controller().record();
    await controller().leave();
    expect(recorder.cancels, 1);
    expect(await attempts(), isEmpty);
    expect(await db.select(db.sessions).get(), isEmpty);
  });
}
