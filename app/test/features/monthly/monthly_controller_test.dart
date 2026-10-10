import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/tasks/monthly_test_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/features/monthly/application/monthly_controller.dart';
import 'package:dilbaz_app/features/monthly/application/monthly_invitation.dart';
import 'package:dilbaz_app/features/monthly/application/monthly_state.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../speaking/speaking_controller_test.dart' show marks, said;

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakeTutorRepository tutor;
  late FakeSpeechRepository speech;
  late FakeAnswerRecorder recorder;
  late DateTime now;
  late ProviderContainer container;
  late MonthlyTestControllerProvider monthly;
  var containerMade = false;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
    profiles = FakeProfileRepository(onboarded: true);
    tutor = FakeTutorRepository()..annotated = marks;
    speech = FakeSpeechRepository(heard: said);
    recorder = FakeAnswerRecorder()..duration = const Duration(seconds: 30);
    now = cardNow;
    containerMade = false;
  });

  tearDown(() async {
    if (containerMade) {
      // Recordings are processed in the background: let them finish.
      await container.read(monthly.notifier).processed();
      container.dispose();
    }
    await db.close();
  });

  MonthlyTestController controller() => container.read(monthly.notifier);

  MonthlyState? current() => container.read(monthly).value;

  Future<MonthlyState> start({bool baseline = false}) async {
    if (containerMade) {
      await container.read(monthly.notifier).processed();
      container.dispose();
    }
    monthly = monthlyTestControllerProvider(baseline: baseline);
    container = ProviderContainer(
      overrides: cardSessionOverrides(
        db: db,
        profiles: profiles,
        tutor: tutor,
        speech: speech,
        recorder: recorder,
        audio: FakePackAudio(),
        player: FakeClipPlayer(),
        clock: () => now,
      ),
    )..listen(monthly, (_, _) {});
    containerMade = true;
    return await container.read(monthly.future);
  }

  /// Through the introduction and the microphone check.
  Future<void> begin({bool baseline = false}) async {
    await start(baseline: baseline);
    controller().begin();
    await controller().checkMicrophone();
    await controller().microphoneOk();
  }

  Future<void> record() async {
    await controller().startRecording();
    await controller().stopRecording();
  }

  /// A whole test: the anchor, then the A2 task.
  Future<MonthlyReport> takeTest() async {
    await begin();
    await record();
    await record();
    return current()! as MonthlyReport;
  }

  test("the anchors, then the level's tasks with their scaffolds", () async {
    expect(
      await start(),
      const MonthlyState.intro(
        baseline: false,
        tasks: 2,
        limit: Duration(minutes: 2),
      ),
    );
    controller().begin();
    expect(current(), const MonthlyState.micCheck(listening: false));
    await controller().checkMicrophone();
    expect(current(), const MonthlyState.micCheck(listening: true));
    await controller().microphoneOk();
    // The check keeps nothing.
    expect(recorder.cancels, 1);

    final anchor = (current()! as MonthlyTask).step;
    expect((anchor.number, anchor.total, anchor.anchor), (1, 2, true));
    expect(anchor.task.key, anchorTask);
    // The same settings every month (docs/06 §3.1).
    expect(anchor.task.preparation, const Duration(seconds: 30));
    expect(anchor.task.phrases, isEmpty);
    await record();
    final level = (current()! as MonthlyTask).step;
    expect((level.number, level.anchor), (2, false));
    expect(level.task.key, cityTask);
    expect(level.task.preparation, const Duration(seconds: 60));
    expect(level.task.phrases, hasLength(3));
  });

  test('each recording is processed and the test is kept once', () async {
    final report = await takeTest();
    expect(report.baseline, isFalse);
    expect(report.tasks, hasLength(2));
    final anchor = report.tasks.first;
    expect(anchor.title, 'Kendini tanıt');
    expect(anchor.anchor, isTrue);
    expect(anchor.spoken, const Duration(milliseconds: 2900));
    expect(anchor.words, 5);
    expect(anchor.clauses, 2);
    expect(anchor.errorFree, 1);
    expect(anchor.previousSpeechRate, isNull);
    // The tutor marks the test more deeply (docs/07 §2).
    expect(tutor.annotateAsked.every((r) => r.assessment), isTrue);

    final assessment = (await db.select(db.assessments).get()).single;
    expect(assessment.kind, 'monthly_speaking');
    expect(assessment.results['month'], '2026-10');
    expect(assessment.results['baseline'], isFalse);
    expect(assessment.results['complete'], isTrue);
    final tasks = assessment.results['tasks']! as List;
    expect(tasks, hasLength(2));
    final recordings = await db.select(db.recordings).get();
    expect(recordings, hasLength(2));
    expect(recordings.every((r) => r.isAssessment), isTrue);
    expect(recordings.every((r) => r.assessmentId == assessment.id), isTrue);
    final session = (await db.select(db.sessions).get()).single;
    expect(session.strandMs, {'output': 60000});
  });

  test("an anchor is reported next to last month's", () async {
    now = DateTime.utc(2026, 9, 2, 9);
    await takeTest();
    now = cardNow;
    speech.heard = 'bada kolu sima dero kolu bada';
    final report = await takeTest();
    final anchor = report.tasks.first;
    expect(anchor.previousSpeechRate, isNotNull);
    expect(anchor.previousClauses, 2);
    expect(anchor.previousErrorFree, 1);
    // Level tasks change, so they are not compared.
    expect(report.tasks.last.previousSpeechRate, isNull);
  });

  test('the month is open until a test (not a baseline) is taken', () async {
    Future<bool> open() {
      // Listened to, as Today does, so that it lives while it loads.
      container.listen(monthlyOpenProvider, (_, _) {});
      return container.read(monthlyOpenProvider.future);
    }

    await start(baseline: true);
    expect(await open(), isTrue);
    await begin(baseline: true);
    await record();
    expect(current(), isA<MonthlyReport>());
    container.invalidate(monthlyOpenProvider);
    expect(await open(), isTrue);

    await takeTest();
    container.invalidate(monthlyOpenProvider);
    expect(await open(), isFalse);

    // After the 7th the invitation waits for next month.
    now = DateTime.utc(2026, 11, 8, 9);
    await start();
    expect(await open(), isFalse);
  });

  test('the baseline: ANC-1 for a minute, kept apart', () async {
    final intro = await start(baseline: true) as MonthlyIntro;
    expect((intro.tasks, intro.limit), (1, const Duration(minutes: 1)));
    await begin(baseline: true);
    final step = (current()! as MonthlyTask).step;
    expect(step.task.key, anchorTask);
    expect(step.task.limit, const Duration(minutes: 1));
    await record();
    expect((current()! as MonthlyReport).baseline, isTrue);
    final results = (await db.select(db.assessments).get()).single.results;
    expect(results['baseline'], isTrue);
    expect(
      await DriftMonthlyTestRepository(db).takenSince(
        FakeAssessmentRepository.zzCourse.id,
        DateTime.utc(2026, 9, 30),
      ),
      isFalse,
    );
  });

  test('leaving keeps what was recorded, marked incomplete', () async {
    await begin();
    await controller().leave();
    expect(await db.select(db.assessments).get(), isEmpty);

    await begin();
    await record();
    await controller().leave();
    await controller().leave();
    final assessment = (await db.select(db.assessments).get()).single;
    expect(assessment.results['complete'], isFalse);
    expect(assessment.results['tasks'], hasLength(1));
  });

  test('a microphone refused, or nothing heard, is said calmly', () async {
    await begin();
    recorder.failure = RecordFailure.device;
    await controller().startRecording();
    expect((current()! as MonthlyFailed).failure, SpeakingFailure.microphone);
    recorder.failure = null;
    controller().tryAgain();
    expect(current(), isA<MonthlyTask>());
    recorder.silent = true;
    await record();
    expect((current()! as MonthlyFailed).failure, SpeakingFailure.silent);
  });

  test(
    'nothing heard in a recording is said, and the task recorded again',
    () async {
      await begin(baseline: true);
      // Silence, or not the course's language: no word comes back.
      speech.heard = '';
      await record();
      expect((current()! as MonthlyFailed).failure, SpeakingFailure.silent);
      // The tutor is not asked to mark nothing.
      expect(tutor.annotateAsked, isEmpty);

      controller().tryAgain();
      expect(current(), isA<MonthlyTask>());
      speech.heard = said;
      await record();
      expect((current()! as MonthlyReport).tasks.single.words, 5);
      final tasks =
          (await db.select(db.assessments).get()).single.results['tasks']!
              as List;
      final recordings = await db.select(db.recordings).get();
      expect(recordings, hasLength(2));
      // Both are kept; only the one with speech in it is the test's.
      final heard = recordings.where((r) => r.hasSpeech).single;
      expect(recordings.where((r) => !r.hasSpeech), hasLength(1));
      expect((tasks.single! as Map)['recording_id'], heard.id);
    },
  );

  test('leaving after nothing was heard keeps no test', () async {
    await begin(baseline: true);
    speech.heard = '';
    await record();
    await controller().leave();
    expect(await db.select(db.assessments).get(), isEmpty);
  });

  test('a recording not written down is kept, and the test goes on', () async {
    await begin();
    speech.failure = SpeechFailure.network;
    await record();
    expect((current()! as MonthlyTask).step.number, 2);
    speech.failure = null;
    await record();
    final report = current()! as MonthlyReport;
    expect(report.tasks.first.words, isNull);
    expect(report.tasks.last.words, 5);
  });

  test('without marks, the first measures stay', () async {
    tutor.annotated = null;
    final report = await takeTest();
    // The engine's own measures; only the tutor marks "eh" as a filler.
    expect(report.tasks.first.words, 6);
    expect(report.tasks.first.speechRate, isNotNull);
    expect(report.tasks.first.clauses, isNull);
  });

  test('without audio consent there is no test (I-18)', () async {
    profiles.audioConsent = false;
    expect(await start(), const MonthlyState.needsConsent());
  });
}
