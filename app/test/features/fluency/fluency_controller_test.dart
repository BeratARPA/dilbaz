import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:dilbaz_app/data/tasks/fluency_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/features/fluency/application/fluency_controller.dart';
import 'package:dilbaz_app/features/fluency/application/fluency_state.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../speaking/speaking_controller_test.dart' show said;

/// A task the learner spoke about, [daysAgo]: written down with speech.
Future<void> spokeAbout(
  AppDatabase db,
  String taskRef, {
  int daysAgo = 1,
  String id = 'spoken',
}) async {
  final recordings = DriftRecordingRepository(
    db,
    now: () => cardNow.subtract(Duration(days: daysAgo)),
  );
  await recordings.create(
    id: id,
    userId: FakeAuthRepository.id,
    courseId: FakeAssessmentRepository.zzCourse.id,
    taskRef: taskRef,
    audioPath: '/recordings/$id.m4a',
    duration: const Duration(seconds: 40),
  );
  const transcript = Transcript(
    text: 'bada kolu',
    provider: 'fake',
    model: 'fake',
    durationMs: 40000,
    words: [
      TranscriptWord(w: 'bada', startMs: 0, endMs: 400),
      TranscriptWord(w: 'kolu', startMs: 500, endMs: 900),
    ],
  );
  await recordings.update(
    id,
    transcript: transcript,
    metrics: SpeechMetrics.of(
      [
        for (final word in transcript.words)
          TimedWord(text: word.w, startMs: word.startMs, endMs: word.endMs),
      ],
      language: PackLanguage(
        rules: const NormalizationRules(version: 1),
        forms: const {},
      ),
    ),
  );
}

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakeSpeechRepository speech;
  late FakeAnswerRecorder recorder;
  late ProviderContainer container;
  var made = false;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
    profiles = FakeProfileRepository(onboarded: true);
    speech = FakeSpeechRepository(heard: said);
    recorder = FakeAnswerRecorder()..duration = const Duration(seconds: 50);
    made = false;
  });

  tearDown(() async {
    if (made) container.dispose();
    await db.close();
  });

  FluencyController controller() =>
      container.read(fluencyControllerProvider.notifier);
  FluencyState? current() => container.read(fluencyControllerProvider).value;

  Future<FluencyState> start() async {
    container = ProviderContainer(
      overrides: cardSessionOverrides(
        db: db,
        profiles: profiles,
        tutor: FakeTutorRepository(),
        speech: speech,
        recorder: recorder,
        audio: FakePackAudio(),
        player: FakeClipPlayer(),
      ),
    )..listen(fluencyControllerProvider, (_, _) {});
    made = true;
    return await container.read(fluencyControllerProvider.future);
  }

  Future<void> round() async {
    await controller().startRound();
    await controller().stopRound();
  }

  Future<List<AttemptRow>> attempts() => (db.select(
    db.attempts,
  )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get();

  test(
    'a known topic only (A12 step 1): none before a speaking task',
    () async {
      expect(await start(), const FluencyState.noTopic());
    },
  );

  test(
    'the topics spoken about, freshest first; the rounds by level',
    () async {
      await spokeAbout(db, homeTask, daysAgo: 3, id: 'home');
      await spokeAbout(db, cityTask, id: 'city');
      final choosing = await start() as FluencyChoosing;
      expect(choosing.topics.map((t) => t.key), [cityTask, homeTask]);
      expect(choosing.topics.first.title, 'Şehrin');
      // The course is at A2: 2, 1.5 and 1 minutes.
      expect(choosing.rounds, const [
        Duration(minutes: 2),
        Duration(seconds: 90),
        Duration(minutes: 1),
      ]);
    },
  );

  test('three rounds, shorter each time; each is an attempt (I-03), the '
      'session goes on fluency', () async {
    await spokeAbout(db, cityTask);
    await start();
    controller().choose(cityTask);
    final first = current()! as FluencyRound;
    expect((first.number, first.recording), (1, false));
    expect(first.task.limit, const Duration(minutes: 2));
    expect(first.task.preparation, Duration.zero);
    expect(first.task.phrases, isEmpty);

    await round();
    final between = current()! as FluencyBetween;
    expect(between.next, const Duration(seconds: 90));
    expect(between.results.single.words, isNotNull);
    expect(between.results.single.speechRate, isNotNull);

    controller().nextRound();
    expect(
      (current()! as FluencyRound).task.limit,
      const Duration(seconds: 90),
    );
    await round();
    controller().nextRound();
    await round();
    final done = current()! as FluencyDone;
    expect(done.results.map((r) => r.number), [1, 2, 3]);
    expect(done.results.map((r) => r.limit.inSeconds), [120, 90, 60]);

    final rounds = await attempts();
    expect(rounds, hasLength(3));
    expect(
      rounds.every((a) => a.activity == DriftFluencyRepository.activity),
      isTrue,
    );
    expect(rounds.every((a) => a.taskRef == cityTask), isTrue);
    expect(rounds.first.parentAttemptId, isNull);
    expect(
      rounds.skip(1).every((a) => a.parentAttemptId == rounds.first.id),
      isTrue,
    );
    expect(rounds[1].prompt, {'round': 2, 'limit_ms': 90000});
    expect(rounds.first.response['text'], said);
    expect(rounds.first.response['metrics'], isA<Map<String, Object?>>());
    final session = (await db.select(db.sessions).get()).single;
    expect(session.strandMs, {'fluency': 150000});
    // Each round goes to the server with the next sync.
    final queued = await db.select(db.outbox).get();
    expect(
      queued.where((o) => o.targetTable == 'attempts').map((o) => o.rowId),
      containsAll([for (final a in rounds) a.id]),
    );

    // Told lately: it goes after the others next time.
    await spokeAbout(db, homeTask, daysAgo: 5, id: 'home');
    container.dispose();
    final next = await start() as FluencyChoosing;
    expect(next.topics.map((t) => t.key), [homeTask, cityTask]);
  });

  test(
    'nothing heard: the round again; no connection: counted unmeasured',
    () async {
      await spokeAbout(db, cityTask);
      await start();
      controller().choose(cityTask);
      speech.heard = '';
      await round();
      expect(
        current(),
        const FluencyState.failed(number: 1, failure: SpeakingFailure.silent),
      );
      expect(await attempts(), isEmpty);

      controller().nextRound();
      speech.failure = SpeechFailure.network;
      await round();
      final between = current()! as FluencyBetween;
      expect(between.results.single.speechRate, isNull);
      expect((await attempts()).single.response, {'source': 'asr'});
    },
  );

  test('leaving keeps the rounds said and owes nothing (I-14)', () async {
    await spokeAbout(db, cityTask);
    await start();
    controller().choose(cityTask);
    await controller().leave();
    expect(await db.select(db.sessions).get(), isEmpty);

    await round();
    await controller().leave();
    await controller().leave();
    expect(await db.select(db.sessions).get(), hasLength(1));
  });

  test('without audio consent there is nothing to record (I-18)', () async {
    profiles.audioConsent = false;
    expect(await start(), const FluencyState.needsConsent());
  });
}
