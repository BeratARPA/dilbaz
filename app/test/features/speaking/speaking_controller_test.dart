import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/data/tutor/annotated_speech.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/cards/application/card_session_state.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_controller.dart';
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

/// Six words: "eh" hesitates, "dero" is the error.
const said = 'bada kolu eh sima dero kolu';

const AnnotatedSpeech marks = AnnotatedSpeech(
  annotation: SpeechAnnotation(
    taskOutcome: TaskOutcome.partial,
    clauses: [
      AnnotatedClause(startI: 0, endI: 1, asUnit: 0, errorFree: true),
      AnnotatedClause(startI: 2, endI: 5, asUnit: 1, errorFree: false),
    ],
    errors: [
      SpeechError(
        startI: 4,
        endI: 4,
        tag: 'zz.form',
        correction: 'deru',
        severity: 2,
      ),
    ],
    fillers: [SpokenFiller(i: 2, kind: FillerKind.l2)],
    strengths: ['bada doğru.'],
    corrections: [
      SpeechCorrection(
        original: 'bada kolu',
        corrected: 'Dero kolu.',
        meaningL1: 'Dero kolu de.',
        tag: 'zz.word',
        severity: 1,
        ladder: CorrectionLadder(h1: 'Bir kelime farklı.', h2: '', h3: ''),
      ),
      SpeechCorrection(
        original: 'sima dero kolu',
        corrected: 'Sima dero.',
        meaningL1: 'Sima dero de.',
        tag: 'zz.form',
        severity: 3,
        ladder: CorrectionLadder(h1: 'Bir kelime fazla.', h2: '', h3: ''),
      ),
    ],
  ),
  catalog: 'qq-zz@1',
  promptVersion: 'speaking_annotate@1',
  provider: 'fake',
  model: 'fake-model',
);

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakeTutorRepository tutor;
  late FakeSpeechRepository speech;
  late FakeAnswerRecorder recorder;
  late ProviderContainer container;
  var containerMade = false;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
    profiles = FakeProfileRepository(onboarded: true);
    tutor = FakeTutorRepository()..annotated = marks;
    speech = FakeSpeechRepository(heard: said);
    recorder = FakeAnswerRecorder()..duration = const Duration(seconds: 30);
    containerMade = false;
  });

  tearDown(() async {
    if (containerMade) container.dispose();
    await db.close();
  });

  SpeakingController controller() =>
      container.read(speakingControllerProvider.notifier);

  SpeakingState? current() => container.read(speakingControllerProvider).value;

  FeedbackView feedback() => (current()! as SpeakingFeedback).view;

  Future<SpeakingState> start() async {
    container = ProviderContainer(
      overrides: cardSessionOverrides(
        db: db,
        profiles: profiles,
        tutor: tutor,
        speech: speech,
        recorder: recorder,
        audio: FakePackAudio(),
        player: FakeClipPlayer(),
      ),
    )..listen(speakingControllerProvider, (_, _) {});
    containerMade = true;
    return await container.read(speakingControllerProvider.future);
  }

  /// Chooses the A2 task and records it.
  Future<void> speak() async {
    await start();
    controller().choose(cityTask);
    await controller().startRecording();
    await controller().stopRecording();
  }

  Future<void> say(String heard) async {
    speech.heard = heard;
    await controller().startSaying();
    await controller().stopSaying();
  }

  Future<List<AttemptRow>> attempts() => (db.select(
    db.attempts,
  )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get();

  group('choosing (I-14)', () {
    test(
      'the level first, then lower ones; anchors are not practice',
      () async {
        final state = await start() as SpeakingChoosing;
        expect(state.suggested.map((t) => t.key), [cityTask, homeTask]);
        expect(state.suggested.first.title, 'Şehrin');
        expect(state.others, isEmpty);
      },
    );

    test('a task done lately goes last', () async {
      await DriftRecordingRepository(
        db,
        now: () => cardNow.subtract(const Duration(days: 3)),
      ).create(
        id: 'rec-0',
        userId: FakeAuthRepository.id,
        courseId: FakeAssessmentRepository.zzCourse.id,
        taskRef: cityTask,
        audioPath: null,
        duration: const Duration(seconds: 40),
      );
      final state = await start() as SpeakingChoosing;
      expect(state.suggested.map((t) => t.key), [homeTask, cityTask]);
    });

    test(
      "the task card: prompt, phrases and the level's preparation",
      () async {
        await start();
        controller().choose(cityTask);
        final task = (current()! as SpeakingPreparing).task;
        expect(task.prompt, 'Şehrin: anlat.');
        // A2: 60 seconds and three phrases, open (docs/02 §3).
        expect(task.preparation, const Duration(seconds: 60));
        expect(task.limit, const Duration(minutes: 2));
        expect(task.phrases.first, (phrase: 'Dero ...', meaning: 'Bada demek'));
        expect(task.phrasesOpen, isTrue);
        controller().chooseAgain();
        expect(
          await container.read(speakingControllerProvider.future),
          isA<SpeakingChoosing>(),
        );
      },
    );

    test('without audio consent nothing is recorded (I-18)', () async {
      profiles.audioConsent = false;
      expect(await start(), const SpeakingState.needsConsent());
    });

    test('without the packs there is no task', () async {
      await db.delete(db.contentPacks).go();
      expect(await start(), const SpeakingState.unavailable());
    });
  });

  group('a recording', () {
    test('is kept, written down, marked and measured', () async {
      await speak();
      final view = feedback();
      expect(view.transcript, said);
      // The hesitation is not a word; 2.9 s from the first word to the last.
      expect(view.words, 5);
      expect(view.spoken, const Duration(milliseconds: 2900));
      expect(view.strengths, ['bada doğru.']);
      expect(view.waiting, isNull);

      final asked = tutor.annotateAsked.single;
      expect(asked.level, CefrLevel.a2);
      expect(asked.prompt, 'Şehrin: anlat.');
      expect(asked.goal, 'Talk about zz.task.city.');
      expect(asked.canDoCodes, ['cd.zz.A2']);
      expect(asked.words, hasLength(6));

      final row = (await db.select(db.recordings).get()).single;
      expect(row.taskRef, cityTask);
      // Named for where it goes on the server; kept here by that name.
      expect(row.audioPath, '${FakeAuthRepository.id}/2026/10/${row.id}.m4a');
      // A task's audio stays here until the server can delete it after
      // 30 days too (F3-08).
      final queued = await db.select(db.outbox).get();
      expect(queued.where((e) => e.op == 'upload'), isEmpty);
      expect(row.durationMs, 30000);
      expect((row.asr!['words']! as List).length, 6);
      expect(row.annotation!['merged'], marks.annotation.toJson());
      expect(row.outcome, 'partial');
      expect(row.metrics!['efc_ratio'], 0.5);
      expect(row.metrics!['words'], 5);
    });

    test('the meaning-breaking correction comes first', () async {
      await speak();
      final corrections = feedback().corrections;
      expect(corrections.map((c) => c.original), [
        'sima dero kolu',
        'bada kolu',
      ]);
      // Nothing is shown before a try (I-01).
      expect(corrections.first.corrected, isNull);
      expect(corrections.first.canReveal, isFalse);
      expect(corrections.first.hints, isEmpty);
    });

    test('nothing heard, or a microphone refused, says so calmly', () async {
      recorder.silent = true;
      await speak();
      expect(current(), isA<SpeakingFailed>());
      expect((current()! as SpeakingFailed).failure, SpeakingFailure.silent);
      controller().tryAgain();
      expect(current(), isA<SpeakingPreparing>());

      recorder
        ..silent = false
        ..failure = RecordFailure.permission;
      await controller().startRecording();
      expect(
        current(),
        isA<SpeakingFailed>().having(
          (f) => f.failure,
          'failure',
          SpeakingFailure.permission,
        ),
      );
    });

    test('recognized silence is not a recording to mark', () async {
      speech.heard = '';
      await speak();
      expect((current()! as SpeakingFailed).failure, SpeakingFailure.silent);
      expect(tutor.annotateAsked, isEmpty);
    });

    test('without a connection it is kept and tried again later', () async {
      speech.failure = SpeechFailure.network;
      await speak();
      final failed = current()! as SpeakingFailed;
      expect(failed.failure, SpeakingFailure.network);
      expect(failed.canRetry, isTrue);
      final row = (await db.select(db.recordings).get()).single;
      expect(row.asr, isNull);

      speech.failure = null;
      await controller().retry();
      expect(current(), isA<SpeakingFeedback>());
      expect(await db.select(db.recordings).get(), hasLength(1));
    });

    test('without the tutor the feedback is the measures alone', () async {
      tutor
        ..annotated = null
        ..annotateFailure = TutorFailure.quota;
      await speak();
      expect(feedback().waiting, TutorFailure.quota);
      expect(feedback().corrections, isEmpty);
      await controller().finish();
      expect(current(), const SpeakingState.done(cards: 0));
      final attempt = (await attempts()).single;
      expect(attempt.activity, 'speaking_task');
      expect(attempt.llm, {
        'route': 'speaking_annotate',
        'pending': true,
        'code': 'quota',
      });
    });
  });

  group('practising the corrections (I-01, I-02)', () {
    test('a miss opens a hint; the answer on request; then a recall', () async {
      await speak();
      controller()
        ..reveal()
        ..nextHint();
      expect(feedback().corrections.first.phase, CorrectionPhase.asking);

      await say('sima dero kolu');
      var correction = feedback().corrections.first;
      expect(correction.phase, CorrectionPhase.asking);
      expect(correction.last, 'sima dero kolu');
      expect(correction.hints, const [Hint.written('Bir kelime fazla.')]);
      expect(correction.canReveal, isTrue);
      expect(correction.corrected, isNull);

      controller().reveal();
      correction = feedback().corrections.first;
      expect(correction.phase, CorrectionPhase.shown);
      expect(correction.corrected, 'Sima dero.');

      controller().nextCorrection();
      expect(feedback().current, 1);
      await say('dero kolu');
      expect(feedback().corrections[1].phase, CorrectionPhase.recalled);
      expect(feedback().corrections[1].corrected, 'Dero kolu.');
      controller().nextCorrection();
      expect(feedback().current, 2);
    });

    test('in silent mode the corrections are typed', () async {
      profiles.silentMode = true;
      await speak();
      expect(feedback().typed, isTrue);
      controller().submit('Sima dero.');
      expect(feedback().corrections.first.phase, CorrectionPhase.recalled);
    });
  });

  group('the end', () {
    test('writes the attempts, the cards and the session', () async {
      await speak();
      await say('sima dero kolu');
      controller()
        ..reveal()
        ..nextCorrection();
      await say('dero kolu');
      controller().nextCorrection();
      await controller().finish();
      expect(current(), const SpeakingState.done(cards: 2));

      final stored = await attempts();
      final task = stored.firstWhere((a) => a.activity == 'speaking_task');
      expect(task.taskRef, cityTask);
      expect(task.errorTags, ['zz.form']);
      expect(task.durationMs, 30000);
      expect(task.response['text'], said);
      expect(task.llm, containsPair('provider', 'fake'));
      final practice = stored
          .where((a) => a.activity == 'speaking_task.correction')
          .toList();
      expect(practice.map((a) => a.verdict), ['wrong', 'correct']);
      expect(practice.every((a) => a.parentAttemptId == task.id), isTrue);
      expect(practice.first.prompt['reference'], 'Sima dero.');

      final row = (await db.select(db.recordings).get()).single;
      expect(row.attemptId, task.id);
      final items = await db.select(db.personalItems).get();
      expect(items.map((i) => (i.textL2, i.glossL1, i.source)), {
        ('Sima dero.', 'Sima dero de.', 'task_correction'),
        ('Dero kolu.', 'Dero kolu de.', 'task_correction'),
      });
      final session = (await db.select(db.sessions).get()).single;
      expect(session.strandMs, {'output': 30000});
      final outbox = {
        for (final entry in await db.select(db.outbox).get()) entry.targetTable,
      };
      expect(
        outbox,
        containsAll(['recordings', 'attempts', 'personal_items', 'sessions']),
      );
    });

    test('a task done again keeps both recordings', () async {
      await speak();
      await controller().redo();
      expect(current(), isA<SpeakingPreparing>());
      await controller().startRecording();
      await controller().stopRecording();
      await controller().finish();
      final tasks = (await attempts()).where(
        (a) => a.activity == 'speaking_task',
      );
      expect(tasks, hasLength(2));
      final session = (await db.select(db.sessions).get()).single;
      expect(session.strandMs, {'output': 60000});
      // The same corrected sentence becomes one card.
      expect(await db.select(db.personalItems).get(), hasLength(2));
    });

    test(
      'leaving keeps what was done, once; before speaking, nothing',
      () async {
        await start();
        await controller().leave();
        expect(await db.select(db.sessions).get(), isEmpty);

        container.dispose();
        containerMade = false;
        await speak();
        await controller().leave();
        await controller().leave();
        expect(
          (await attempts()).where((a) => a.activity == 'speaking_task'),
          hasLength(1),
        );
        expect(await db.select(db.personalItems).get(), hasLength(2));
        expect(await db.select(db.sessions).get(), hasLength(1));
      },
    );
  });
}
