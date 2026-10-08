import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/data/tutor/annotated_speech.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pack_fixture.dart';

const userId = '0192f5a0-0000-7000-8000-000000000001';
const courseId = '0192f5a0-0000-7000-8000-0000000000c1';
const taskRef = 'zz.task.home';

const correction = SpeechCorrection(
  original: 'bada kulu',
  corrected: 'Bada kolu.',
  meaningL1: 'Bada kolu de.',
  tag: 'zz.form',
  severity: 2,
  ladder: CorrectionLadder(h1: 'Biçim.', h2: '', h3: ''),
);

const AnnotatedSpeech marks = AnnotatedSpeech(
  annotation: SpeechAnnotation(
    taskOutcome: TaskOutcome.notDone,
    errors: [
      SpeechError(
        startI: 1,
        endI: 1,
        tag: 'zz.form',
        correction: 'kolu',
        severity: 2,
      ),
      SpeechError(
        startI: 1,
        endI: 1,
        tag: 'zz.form',
        correction: 'kolu',
        severity: 2,
      ),
    ],
    corrections: [correction],
  ),
  catalog: 'qq-zz@1',
  promptVersion: 'speaking_annotate@1',
  provider: 'gemini',
  model: 'gemini-3.5-flash',
);

const transcript = Transcript(
  text: 'bada kulu',
  provider: 'deepgram',
  model: 'nova-3',
  durationMs: 1200,
  words: [
    TranscriptWord(w: 'bada', startMs: 0, endMs: 400, conf: 0.9),
    TranscriptWord(w: 'kulu', startMs: 500, endMs: 900),
  ],
);

void main() {
  late AppDatabase db;
  late DateTime now;
  var next = 0;

  setUp(() {
    db = memoryDatabase();
    now = DateTime.utc(2026, 10, 1, 9);
    next = 0;
  });
  tearDown(() => db.close());

  DriftRecordingRepository repository() =>
      DriftRecordingRepository(db, now: () => now, newId: () => 'id-${next++}');

  Future<void> create(DriftRecordingRepository recordings) => recordings.create(
    id: 'rec-1',
    userId: userId,
    courseId: courseId,
    taskRef: taskRef,
    audioPath: '/recordings/rec-1.m4a',
    duration: const Duration(seconds: 70),
  );

  test(
    'a recording is kept first, then filled in as it is processed',
    () async {
      final recordings = repository();
      await create(recordings);
      var row = (await recordings.recording('rec-1'))!;
      expect(row.taskRef, taskRef);
      expect(row.durationMs, 70000);
      expect(row.asr, isNull);
      expect(row.isAssessment, isFalse);

      await recordings.update('rec-1', transcript: transcript);
      await recordings.update('rec-1', annotated: marks);
      final metrics = SpeechMetrics.fromJson(const {
        'speaking_ms': 900,
        'words': 2,
        'speech_rate': 133.3,
        'articulation_rate': null,
        'mlr': 2,
        'long_pauses_per_min': 0,
        'filled_pauses_per_min': 0,
        'mid_clause_pause_ratio': null,
        'l1_fillers_per_min': 0,
        'repairs_per_min': 0,
        'efc_ratio': 0,
        'errors_per_100w': 50,
        'errors_by_tag': {'zz.form': 50},
        'mean_clause_length': null,
        'subordination': null,
        'mtld': null,
        'connector_types': 0,
        'beyond_2k_share': null,
      });
      await recordings.update('rec-1', metrics: metrics);

      row = (await recordings.recording('rec-1'))!;
      expect(row.asr, {
        'provider': 'deepgram',
        'model': 'nova-3',
        'words': [
          {'w': 'bada', 'start_ms': 0, 'end_ms': 400, 'conf': 0.9},
          {'w': 'kulu', 'start_ms': 500, 'end_ms': 900, 'conf': null},
        ],
      });
      expect(row.annotation!['merged'], marks.annotation.toJson());
      expect((row.annotation!['runs']! as List).single, marks.toJson());
      expect(row.outcome, 'not_done');
      expect(row.metrics, metrics.toJson());
      // A state row: every change waits in the outbox as an upsert.
      final outbox = await db.select(db.outbox).get();
      expect(outbox.map((e) => (e.targetTable, e.rowId, e.op)).toSet(), {
        ('recordings', 'rec-1', 'upsert'),
      });
    },
  );

  test("the task's attempt and its practice, chained (I-03)", () async {
    final recordings = repository();
    await create(recordings);
    final attemptId = await recordings.recordAttempt(
      userId: userId,
      courseId: courseId,
      deviceId: 'device-1',
      recordingId: 'rec-1',
      taskRef: taskRef,
      prompt: 'Evini anlat.',
      at: now,
      transcript: transcript,
      annotated: marks,
    );
    await recordings.recordPractice(
      userId: userId,
      courseId: courseId,
      deviceId: 'device-1',
      parentAttemptId: attemptId,
      taskRef: taskRef,
      correction: correction,
      answers: [
        (
          text: 'bada kulu',
          heard: true,
          verdict: Verdict.wrong,
          hintsUsed: 0,
          at: now,
        ),
        (
          text: 'Bada kolu.',
          heard: false,
          verdict: Verdict.correct,
          hintsUsed: 1,
          at: now,
        ),
      ],
    );

    final stored = await (db.select(
      db.attempts,
    )..orderBy([(t) => OrderingTerm(expression: t.id)])).get();
    final task = stored.firstWhere((a) => a.id == attemptId);
    expect(task.activity, 'speaking_task');
    expect(task.taskRef, taskRef);
    expect(task.prompt, {'prompt_l1': 'Evini anlat.'});
    expect(task.response, {
      'source': 'asr',
      'recording_id': 'rec-1',
      'text': 'bada kulu',
      'asr': {'provider': 'deepgram', 'model': 'nova-3'},
    });
    // Each tag once.
    expect(task.errorTags, ['zz.form']);
    expect(task.durationMs, 70000);
    expect(task.llm, {
      'route': 'speaking_annotate',
      'pending': false,
      'provider': 'gemini',
      'model': 'gemini-3.5-flash',
      'catalog': 'qq-zz@1',
    });
    final practice = stored.where((a) => a.activity != 'speaking_task').toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    expect(practice.map((a) => a.verdict), ['wrong', 'correct']);
    expect(practice.first.parentAttemptId, attemptId);
    expect(practice.last.parentAttemptId, practice.first.id);
    expect(practice.last.response, {'text': 'Bada kolu.', 'source': 'typed'});
    expect(practice.last.hintsUsed, 1);
    expect(practice.first.prompt['reference'], 'Bada kolu.');
    expect((await recordings.recording('rec-1'))!.attemptId, attemptId);
  });

  test('an attempt without marks waits for them', () async {
    final recordings = repository();
    await create(recordings);
    final id = await recordings.recordAttempt(
      userId: userId,
      courseId: courseId,
      deviceId: 'device-1',
      recordingId: 'rec-1',
      taskRef: taskRef,
      prompt: 'Evini anlat.',
      at: now,
      llmCode: 'network',
    );
    final attempt = await (db.select(
      db.attempts,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(attempt.llm, {
      'route': 'speaking_annotate',
      'pending': true,
      'code': 'network',
    });
    expect(attempt.response, {'source': 'asr', 'recording_id': 'rec-1'});
    expect(attempt.errorTags, isEmpty);
  });

  test("corrected sentences become the learner's own items", () async {
    final ids = await repository().addCorrections(
      userId: userId,
      courseId: courseId,
      sentences: [
        (sentence: ' Bada kolu. ', meaning: 'Bada kolu de.', lemmas: ['bada']),
      ],
    );
    final item = (await db.select(db.personalItems).get()).single;
    expect(ids, [item.id]);
    expect(item.kind, 'sentence');
    expect(item.textL2, 'Bada kolu.');
    expect(item.glossL1, 'Bada kolu de.');
    expect(item.source, 'task_correction');
    expect(item.lemmas, ['bada']);
    final outbox = (await db.select(db.outbox).get()).single;
    expect((outbox.targetTable, outbox.op), ('personal_items', 'upsert'));
  });

  test('the tasks recorded lately, per course', () async {
    final recordings = repository();
    await create(recordings);
    now = now.add(const Duration(days: 20));
    await recordings.create(
      id: 'rec-2',
      userId: userId,
      courseId: courseId,
      taskRef: 'zz.task.city',
      audioPath: null,
      duration: const Duration(seconds: 50),
    );
    await recordings.create(
      id: 'rec-3',
      userId: userId,
      courseId: 'another-course',
      taskRef: 'zz.task.park',
      audioPath: null,
      duration: const Duration(seconds: 50),
    );
    expect(
      await recordings.taskRefsSince(
        courseId,
        now.subtract(const Duration(days: 14)),
      ),
      {'zz.task.city'},
    );
  });
}
