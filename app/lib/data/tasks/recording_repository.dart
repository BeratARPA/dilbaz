import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:dilbaz_app/data/tutor/annotated_speech.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// One answer while practising a correction: what was said or typed, how
/// it was judged, the hints open before it, and when it came.
typedef PracticeAnswer = ({
  String text,
  bool heard,
  Verdict verdict,
  int hintsUsed,
  DateTime at,
});

/// A corrected sentence of a speaking task, for the learner's own items.
typedef CorrectedSentence = ({
  String sentence,

  /// What it means in the learner's language: its card's prompt.
  String meaning,
  List<String> lemmas,
});

/// Speech in a recording, for before/after listening (docs/06 §2 part 4).
extension RecordingSpeech on RecordingRow {
  /// Whether speech was heard in it. Written down with nothing measured or
  /// marked in it (silence, or not the course's language), it has none;
  /// not written down yet, it may.
  bool get hasSpeech => asr == null || metrics != null || annotation != null;
}

/// Whether the course has a test recording to listen back to: kept, with
/// speech in it. Until then the baseline is offered (docs/06 §2 part 4).
bool hasFirstRecording(Iterable<RecordingRow> recordings) => recordings.any(
  (row) => row.isAssessment && row.audioPath != null && row.hasSpeech,
);

/// Speaking task and test recordings (docs/13-data-model.md §2.4
/// `recordings`): the audio's place, the transcript, the marks and the
/// measures, filled in as processing goes on; and what a task leaves
/// behind: its attempt (I-03) and the corrected sentences as cards.
abstract interface class RecordingRepository {
  /// A new recording of [taskRef]. [audioPath] names its audio by where it
  /// goes on the server (`recordingStoragePath`); a test recording's audio
  /// is queued to go up with the row. Null where audio cannot be kept.
  Future<void> create({
    required String id,
    required String userId,
    required String courseId,
    required String taskRef,
    required String? audioPath,
    required Duration duration,
    bool isAssessment = false,
    String? assessmentId,
  });

  /// What processing found so far; null leaves a field as it is.
  Future<void> update(
    String id, {
    Transcript? transcript,
    AnnotatedSpeech? annotated,
    SpeechMetrics? metrics,
  });

  Future<RecordingRow?> recording(String id);

  /// The tasks recorded since [since] (UTC).
  Future<Set<String>> taskRefsSince(String courseId, DateTime since);

  /// Every recording of the course, oldest first.
  Future<List<RecordingRow>> recordings(String courseId);

  /// The task's attempt, written once when the learner leaves its
  /// feedback; it is linked to the recording. Returns its id.
  Future<String> recordAttempt({
    required String userId,
    required String courseId,
    required String deviceId,
    required String recordingId,
    required String taskRef,
    required String prompt,
    required DateTime at,
    Transcript? transcript,
    AnnotatedSpeech? annotated,
    String? llmCode,
  });

  /// The answers given while practising one correction, chained after
  /// [parentAttemptId] (the task's attempt), each written once (I-03).
  Future<void> recordPractice({
    required String userId,
    required String courseId,
    required String deviceId,
    required String parentAttemptId,
    required String taskRef,
    required SpeechCorrection correction,
    required List<PracticeAnswer> answers,
  });

  /// The corrected sentences as the learner's own items (docs/03 A11
  /// step 5); their ids.
  Future<List<String>> addCorrections({
    required String userId,
    required String courseId,
    required List<CorrectedSentence> sentences,
  });
}

String _uuidV7() => const Uuid().v7();

class DriftRecordingRepository implements RecordingRepository {
  new(this._db, {this._now = nowUtc, this._newId = _uuidV7});

  final AppDatabase _db;
  final DateTime Function() _now;
  final String Function() _newId;

  static const _recordings = 'recordings';
  static const _attempts = 'attempts';
  static const _personalItems = 'personal_items';
  static const _activity = 'speaking_task';
  static const _practice = 'speaking_task.correction';
  static const _route = 'speaking_annotate';
  static const _source = 'task_correction';

  Future<void> _queue(String table, String rowId, String op) => _db
      .into(_db.outbox)
      .insert(OutboxCompanion.insert(targetTable: table, rowId: rowId, op: op));

  @override
  Future<void> create({
    required String id,
    required String userId,
    required String courseId,
    required String taskRef,
    required String? audioPath,
    required Duration duration,
    bool isAssessment = false,
    String? assessmentId,
  }) => _db.transaction(() async {
    final now = _now();
    await _db
        .into(_db.recordings)
        .insert(
          RecordingsCompanion.insert(
            id: id,
            profileId: userId,
            courseId: courseId,
            taskRef: Value(taskRef),
            audioPath: Value(audioPath),
            durationMs: duration.inMilliseconds,
            isAssessment: Value(isAssessment),
            assessmentId: Value(assessmentId),
            updatedAt: Value(now),
            createdAt: Value(now),
            pendingPush: const Value(true),
          ),
        );
    await _queue(_recordings, id, 'upsert');
    // Test recordings are kept until the learner removes them, so their
    // audio goes up. A task's audio is deleted after 30 days (docs/14 §4);
    // it waits until the server can delete it too (F3-08).
    if (audioPath != null && isAssessment) {
      await _queue(_recordings, id, 'upload');
    }
  });

  /// `recordings.asr`: the recognizer and its words (docs/13 §2.4).
  static Map<String, Object?> _asr(Transcript transcript) => {
    'provider': transcript.provider,
    'model': transcript.model,
    'words': [
      for (final word in transcript.words)
        TimedWord(
          text: word.w,
          startMs: word.startMs,
          endMs: word.endMs,
          confidence: word.conf,
        ).toJson(),
    ],
  };

  @override
  Future<void> update(
    String id, {
    Transcript? transcript,
    AnnotatedSpeech? annotated,
    SpeechMetrics? metrics,
  }) => _db.transaction(() async {
    await (_db.update(_db.recordings)..where((t) => t.id.equals(id))).write(
      RecordingsCompanion(
        asr: transcript == null
            ? const Value.absent()
            : Value(_asr(transcript)),
        // One run until the monthly test marks twice (docs/06 §3.2).
        annotation: annotated == null
            ? const Value.absent()
            : Value({
                'runs': [annotated.toJson()],
                'merged': annotated.annotation.toJson(),
              }),
        outcome: annotated == null
            ? const Value.absent()
            : Value(_outcome(annotated.annotation.taskOutcome)),
        metrics: metrics == null
            ? const Value.absent()
            : Value(metrics.toJson()),
        updatedAt: Value(_now()),
        pendingPush: const Value(true),
      ),
    );
    await _queue(_recordings, id, 'upsert');
  });

  static String _outcome(TaskOutcome outcome) => switch (outcome) {
    TaskOutcome.done => 'done',
    TaskOutcome.partial => 'partial',
    TaskOutcome.notDone => 'not_done',
  };

  @override
  Future<RecordingRow?> recording(String id) => (_db.select(
    _db.recordings,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  @override
  Future<List<RecordingRow>> recordings(String courseId) =>
      (_db.select(_db.recordings)
            ..where((t) => t.courseId.equals(courseId))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();

  @override
  Future<Set<String>> taskRefsSince(String courseId, DateTime since) async => {
    for (final row
        in await (_db.select(_db.recordings)..where(
              (t) =>
                  t.courseId.equals(courseId) &
                  t.createdAt.isBiggerOrEqualValue(since),
            ))
            .get())
      ?row.taskRef,
  };

  @override
  Future<void> recordPractice({
    required String userId,
    required String courseId,
    required String deviceId,
    required String parentAttemptId,
    required String taskRef,
    required SpeechCorrection correction,
    required List<PracticeAnswer> answers,
  }) => _db.transaction(() async {
    var parent = parentAttemptId;
    for (final answer in answers) {
      final id = _newId();
      await _db
          .into(_db.attempts)
          .insert(
            AttemptsCompanion.insert(
              id: id,
              profileId: userId,
              courseId: courseId,
              deviceId: deviceId,
              activity: _practice,
              taskRef: Value(taskRef),
              parentAttemptId: Value(parent),
              prompt: {
                'original': correction.original,
                'reference': correction.corrected,
                'tag': correction.tag,
              },
              response: {
                'text': answer.text,
                'source': answer.heard ? 'asr' : 'typed',
              },
              verdict: Value(answer.verdict.code),
              hintsUsed: Value(answer.hintsUsed),
              hintMaxLevel: Value(answer.hintsUsed),
              createdAtClient: answer.at,
              createdAt: Value(_now()),
              pendingPush: const Value(true),
            ),
          );
      await _queue(_attempts, id, 'insert');
      parent = id;
    }
  });

  @override
  Future<String> recordAttempt({
    required String userId,
    required String courseId,
    required String deviceId,
    required String recordingId,
    required String taskRef,
    required String prompt,
    required DateTime at,
    Transcript? transcript,
    AnnotatedSpeech? annotated,
    String? llmCode,
  }) => _db.transaction(() async {
    final id = _newId();
    final recording = await this.recording(recordingId);
    await _db
        .into(_db.attempts)
        .insert(
          AttemptsCompanion.insert(
            id: id,
            profileId: userId,
            courseId: courseId,
            deviceId: deviceId,
            activity: _activity,
            taskRef: Value(taskRef),
            prompt: {'prompt_l1': prompt},
            response: {
              'source': 'asr',
              'recording_id': recordingId,
              'text': ?transcript?.text,
              if (transcript != null)
                'asr': {
                  'provider': transcript.provider,
                  'model': transcript.model,
                },
            },
            errorTags: Value([
              ...{
                for (final error
                    in annotated?.annotation.errors ?? const <SpeechError>[])
                  error.tag,
              },
            ]),
            durationMs: Value(recording?.durationMs),
            llm: Value(
              annotated == null
                  ? {'route': _route, 'pending': true, 'code': ?llmCode}
                  : {
                      'route': _route,
                      'pending': false,
                      'provider': annotated.provider,
                      'model': annotated.model,
                      'catalog': annotated.catalog,
                    },
            ),
            createdAtClient: at,
            createdAt: Value(_now()),
            pendingPush: const Value(true),
          ),
        );
    await _queue(_attempts, id, 'insert');
    await (_db.update(
      _db.recordings,
    )..where((t) => t.id.equals(recordingId))).write(
      RecordingsCompanion(
        attemptId: Value(id),
        updatedAt: Value(_now()),
        pendingPush: const Value(true),
      ),
    );
    await _queue(_recordings, recordingId, 'upsert');
    return id;
  });

  @override
  Future<List<String>> addCorrections({
    required String userId,
    required String courseId,
    required List<CorrectedSentence> sentences,
  }) => _db.transaction(() async {
    final now = _now();
    final ids = <String>[];
    for (final (:sentence, :meaning, :lemmas) in sentences) {
      final id = _newId();
      await _db
          .into(_db.personalItems)
          .insert(
            PersonalItemsCompanion.insert(
              id: id,
              profileId: userId,
              courseId: courseId,
              kind: 'sentence',
              textL2: sentence.trim(),
              source: _source,
              glossL1: Value(meaning.trim()),
              lemmas: Value(lemmas),
              updatedAt: Value(now),
              createdAt: Value(now),
              pendingPush: const Value(true),
            ),
          );
      await _queue(_personalItems, id, 'upsert');
      ids.add(id);
    }
    return ids;
  });
}
