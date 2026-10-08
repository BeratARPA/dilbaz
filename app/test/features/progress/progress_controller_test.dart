import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/attempt_draft.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/data/tutor/annotated_speech.dart';
import 'package:dilbaz_app/features/progress/application/progress_controller.dart';
import 'package:dilbaz_app/features/progress/application/progress_view.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';

final String courseId = FakeAssessmentRepository.zzCourse.id;

/// "bada" right, "dero" marked wrong.
AnnotatedSpeech marked(TaskOutcome outcome) => AnnotatedSpeech(
  annotation: SpeechAnnotation(
    taskOutcome: outcome,
    clauses: const [
      AnnotatedClause(startI: 0, endI: 1, asUnit: 0, errorFree: true),
      AnnotatedClause(startI: 2, endI: 3, asUnit: 1, errorFree: false),
    ],
    errors: const [
      SpeechError(
        startI: 3,
        endI: 3,
        tag: 'zz.form',
        correction: 'deru',
        severity: 1,
      ),
    ],
  ),
  catalog: 'qq-zz@1',
  promptVersion: 'speaking_annotate@1',
  provider: 'fake',
  model: 'fake-model',
);

const heard = Transcript(
  text: 'bada kolu sima dero',
  provider: 'fake',
  model: 'fake',
  durationMs: 2000,
  words: [
    TranscriptWord(w: 'bada', startMs: 0, endMs: 400),
    TranscriptWord(w: 'kolu', startMs: 500, endMs: 900),
    TranscriptWord(w: 'sima', startMs: 1000, endMs: 1400),
    TranscriptWord(w: 'dero', startMs: 1500, endMs: 1900),
  ],
);

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Cards of bada and dero recalled a week and more ago.
  Future<void> recall(String itemRef) async {
    final cards = DriftCardRepository(
      db,
      now: () => cardNow.subtract(const Duration(days: 20)),
    );
    final card = await cards.introduce(
      userId: FakeAuthRepository.id,
      courseId: courseId,
      itemRef: itemRef,
      mode: CardMode.speak,
    );
    await cards.recordReview(
      userId: FakeAuthRepository.id,
      courseId: courseId,
      deviceId: 'device-1',
      card: card,
      attempts: [
        AttemptDraft(
          activity: cardActivity(CardMode.speak),
          prompt: const {},
          response: const {'text': 'x', 'source': 'asr'},
          createdAtClient: cardNow.subtract(const Duration(days: 20)),
          verdict: 'correct',
          targetOk: true,
        ),
      ],
      rating: ReviewRating.good,
      after: CardMemory(
        fsrsCardId: 1,
        state: MemoryState.review,
        due: cardNow.add(const Duration(days: 5)),
        stability: 12,
        difficulty: 5,
        lastReview: cardNow.subtract(const Duration(days: 20)),
        reps: 1,
      ),
    );
  }

  /// A recording of [taskRef] made [daysAgo], transcribed and marked.
  Future<void> recorded(
    String id,
    String taskRef, {
    required int daysAgo,
    TaskOutcome outcome = TaskOutcome.done,
    bool assessment = false,
  }) async {
    final recordings = DriftRecordingRepository(
      db,
      now: () => cardNow.subtract(Duration(days: daysAgo)),
    );
    await recordings.create(
      id: id,
      userId: FakeAuthRepository.id,
      courseId: courseId,
      taskRef: taskRef,
      audioPath: '/recordings/$id.m4a',
      duration: const Duration(seconds: 40),
      isAssessment: assessment,
    );
    await recordings.update(id, transcript: heard, annotated: marked(outcome));
    await recordings.update(
      id,
      metrics: SpeechMetrics.of(
        [
          for (final word in heard.words)
            TimedWord(text: word.w, startMs: word.startMs, endMs: word.endMs),
        ],
        language: PackLanguage(
          rules: const NormalizationRules(version: 1),
          forms: const {},
        ),
        annotation: marked(outcome).annotation,
      ),
    );
  }

  Future<ProgressView> read() async {
    container = ProviderContainer(
      overrides: cardSessionOverrides(
        db: db,
        profiles: FakeProfileRepository(onboarded: true),
        tutor: FakeTutorRepository(),
        speech: FakeSpeechRepository(),
        recorder: FakeAnswerRecorder(),
        audio: FakePackAudio(),
        player: FakeClipPlayer(),
      ),
    );
    final view = await container.read(progressProvider.future);
    return view!;
  }

  test(
    'counts: recalled items, used ones only when used on two days',
    () async {
      await recall(bada);
      await recall(sima);
      await recorded('rec-1', homeTask, daysAgo: 5);
      var view = await read();
      expect(view.counts, (known: 2, recallable: 2, durable: 0, used: 0));

      container.dispose();
      await recorded('rec-2', cityTask, daysAgo: 2);
      view = await read();
      // bada and sima were said right on two days; dero was marked wrong
      // and has no card anyway.
      expect(view.counts, (known: 2, recallable: 2, durable: 0, used: 2));
    },
  );

  test('can-dos: none, attempted, shown, established', () async {
    await recorded('rec-1', homeTask, daysAgo: 5);
    await recorded('rec-2', anchorTask, daysAgo: 2, assessment: true);
    await recorded('rec-3', cityTask, daysAgo: 1, outcome: TaskOutcome.partial);
    final view = await read();
    expect(view.canDos, [
      // Home and the anchor are both A1: two days, two prompts.
      (
        summary: 'Kendini anlatabilirsin.',
        status: CanDoStatus.established,
        refresh: false,
      ),
      (
        summary: 'Şehrini anlatabilirsin.',
        status: CanDoStatus.attempted,
        refresh: false,
      ),
    ]);
  });

  test('anchors: the first, an earlier month and the latest', () async {
    // August, September and October of the anchor; a practice task too.
    await recorded('aug', anchorTask, daysAgo: 60, assessment: true);
    await recorded('sep', anchorTask, daysAgo: 30, assessment: true);
    await recorded('oct', anchorTask, daysAgo: 0, assessment: true);
    await recorded('home', homeTask, daysAgo: 1);
    final view = await read();
    final anchor = view.anchors.single;
    expect(anchor.title, 'Kendini tanıt');
    expect(anchor.recordings.map((r) => (r.moment, r.path)), [
      (AnchorMoment.first, '/recordings/aug.m4a'),
      (AnchorMoment.previous, '/recordings/sep.m4a'),
      (AnchorMoment.latest, '/recordings/oct.m4a'),
    ]);
    expect(anchor.months, hasLength(3));
    final october = anchor.months.last;
    expect(october.clauses, 2);
    expect(october.errorFree, 1);
    expect(october.speechRate, isNotNull);
  });

  test('before any data: zeros and no recordings', () async {
    final view = await read();
    expect(view.counts, (known: 0, recallable: 0, durable: 0, used: 0));
    expect(view.vocabulary, isNull);
    expect(view.anchors.single.recordings, isEmpty);
  });
}
