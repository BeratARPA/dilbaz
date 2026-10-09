import 'dart:async';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/audio/recorder_config.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/data/tasks/monthly_test_repository.dart';
import 'package:dilbaz_app/data/tasks/speaking_task.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/data/tutor/speaking_annotate_request.dart';
import 'package:dilbaz_app/features/monthly/application/monthly_state.dart';
import 'package:dilbaz_app/features/speaking/application/recording_pipeline.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_controller.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'monthly_controller.g.dart';

/// What the test works with, found once.
typedef _Context = ({
  String userId,
  String courseId,
  String deviceId,
  String l1,
  String l2,
  CefrLevel level,
  bool explainInL1,
  MeasureKit kit,
});

/// The monthly speaking test (A23, docs/06 §3): a microphone check, the
/// three anchors with the same settings every month (30 s to prepare, no
/// phrases, at most two minutes, one at A0–A1), then two tasks of the
/// level with its scaffolds. Each recording is written down and measured
/// before the next task, so that one with nothing heard in it is recorded
/// again; the tutor marks it once (v1) while the test goes on. The report
/// compares the anchors with last month; no grade (§3.4).
///
/// [baseline]: the placement test's optional first recording, ANC-1 for a
/// minute (§2 part 4), kept for before/after listening.
@riverpod
class MonthlyTestController extends _$MonthlyTestController {
  late _Context _context;
  var _tasks = const <SpeakingTask>[];
  var _steps = const <TestStep>[];
  var _index = 0;
  Timer? _limit;
  late String _assessmentId;
  final _pending = <Future<MonthlyTaskResult>>[];
  final _recorded = <MonthlyTaskResult>[];
  DateTime? _startedAt;
  Duration _speaking = Duration.zero;
  var _saved = false;

  /// The anchors' fixed settings (docs/06 §3.1).
  static const anchorPreparation = Duration(seconds: 30);
  static const shortLimit = Duration(minutes: 1);

  @override
  Future<MonthlyState> build({bool baseline = false}) async {
    ref
      ..onDispose(() => _limit?.cancel())
      ..watch(answerRecorderProvider);
    final userId = ref.watch(authRepositoryProvider).userId;
    if (userId == null) return const MonthlyState.unavailable();
    final course = await ref.watch(assessmentRepositoryProvider).course(userId);
    final settings = await ref
        .watch(profileRepositoryProvider)
        .studySettings(userId);
    final language = await ref.watch(cardContentRepositoryProvider).language();
    final content = ref.watch(taskContentRepositoryProvider);
    if (course == null || settings == null || language == null) {
      return const MonthlyState.unavailable();
    }
    final all = await content.speakingTasks();
    final now = ref.read(clockProvider)();
    final local = now.toLocal();
    final keys = baseline
        ? [
            for (final task in all)
              if (task.anchor == 'ANC-1') task.key,
          ]
        : monthlyTasks(
            tasks: [
              for (final task in all)
                (key: task.key, level: task.level, anchor: task.anchor),
            ],
            level: course.level,
            month: local.year * 12 + local.month - 1,
          );
    final byKey = {for (final task in all) task.key: task};
    _tasks = [for (final key in keys) ?byKey[key]];
    if (_tasks.isEmpty) return const MonthlyState.unavailable();
    if (!settings.audioConsent) return const MonthlyState.needsConsent();

    final scaffolds = Scaffolds.forLevel(course.level);
    final anchorLimit = baseline || course.level.isAtMost(CefrLevel.a1)
        ? shortLimit
        : RecorderConfig.taskLimit;
    _steps = [
      for (final (i, task) in _tasks.indexed)
        TestStep(
          task: TaskView(
            key: task.key,
            title: task.title,
            prompt: task.prompt,
            preparation: task.anchor != null
                ? anchorPreparation
                : scaffolds.taskPreparation,
            limit: task.anchor != null ? anchorLimit : RecorderConfig.taskLimit,
            phrases: task.anchor != null
                ? const []
                : [
                    for (final (j, phrase) in task.phrases.indexed)
                      (
                        phrase: phrase,
                        meaning: j < task.phraseMeanings.length
                            ? task.phraseMeanings[j]
                            : '',
                      ),
                  ],
            phrasesOpen: scaffolds.taskPhrases,
          ),
          number: i + 1,
          total: _tasks.length,
          anchor: task.anchor != null,
          recording: false,
        ),
    ];
    _context = (
      userId: userId,
      courseId: course.id,
      deviceId: await ref.watch(deviceRepositoryProvider).deviceId(userId),
      l1: settings.l1,
      l2: course.l2,
      level: course.level,
      explainInL1: scaffolds.explainInL1,
      kit: (
        language: language,
        connectors: await content.connectors(),
        ranks: await content.lemmaRanks(),
      ),
    );
    _assessmentId = const Uuid().v7();
    return MonthlyState.intro(
      baseline: baseline,
      tasks: _tasks.length,
      limit: anchorLimit,
    );
  }

  /// From the introduction to the microphone check.
  void begin() {
    if (state.value is! MonthlyIntro) return;
    _startedAt = ref.read(clockProvider)();
    state = const AsyncData(MonthlyState.micCheck(listening: false));
  }

  /// Listens for the level meter; nothing is kept.
  Future<void> checkMicrophone() async {
    if (state.value case MonthlyMicCheck(listening: false)) {
      final started = await ref.read(answerRecorderProvider).start();
      if (!ref.mounted || started is Err) return;
      state = const AsyncData(MonthlyState.micCheck(listening: true));
    }
  }

  /// On to the first task.
  Future<void> microphoneOk() async {
    if (state.value case MonthlyMicCheck(:final listening)) {
      if (listening) await ref.read(answerRecorderProvider).cancel();
      if (!ref.mounted) return;
      _index = 0;
      state = AsyncData(MonthlyState.task(_steps[0]));
    }
  }

  TestStep get _step => _steps[_index];

  Future<void> startRecording() async {
    final ready = switch (state.value) {
      MonthlyTask(step: TestStep(recording: false)) || MonthlyFailed() => true,
      _ => false,
    };
    if (!ready) return;
    final started = await ref.read(answerRecorderProvider).start();
    if (!ref.mounted) return;
    if (started case Err(:final error)) {
      state = AsyncData(
        MonthlyState.failed(
          _step,
          error == RecordFailure.permission
              ? SpeakingFailure.permission
              : SpeakingFailure.microphone,
        ),
      );
      return;
    }
    state = AsyncData(MonthlyState.task(_step.copyWith(recording: true)));
    _limit = Timer(_step.task.limit, () => unawaited(stopRecording()));
  }

  /// Keeps the recording and writes it down. With nothing heard in it
  /// (silence, or not the course's language) the task is recorded again;
  /// otherwise the test goes on while the tutor marks it.
  Future<void> stopRecording() async {
    final current = state.value;
    if (current is! MonthlyTask || !current.step.recording) return;
    _limit?.cancel();
    final audio = await ref.read(answerRecorderProvider).stop();
    if (!ref.mounted) return;
    if (audio == null) {
      state = AsyncData(MonthlyState.failed(_step, SpeakingFailure.silent));
      return;
    }
    _speaking += audio.duration;
    final task = _tasks[_index];
    final id = const Uuid().v7();
    final pipeline = ref.read(recordingPipelineProvider);
    await pipeline.keep(
      id: id,
      userId: _context.userId,
      courseId: _context.courseId,
      taskRef: task.key,
      audio: audio,
      isAssessment: true,
      assessmentId: _assessmentId,
    );
    if (!ref.mounted) return;
    final kept = (
      taskRef: task.key,
      recordingId: id,
      anchor: task.anchor != null,
      metrics: null,
      clauses: null,
      errorFree: null,
    );
    // Saved even when the learner leaves while it is written down.
    _recorded.add(kept);
    state = const AsyncData(MonthlyState.hearing());
    switch (await pipeline.transcribe(id, audio)) {
      case Err():
        // Not written down: kept as it is, and the test goes on.
        if (!ref.mounted) return;
        _pending.add(Future.value(kept));
      case Ok(value: final transcript):
        final words = timedWords(transcript);
        final measured = await pipeline.measure(id, words, _context.kit);
        if (!ref.mounted) return;
        if (measured == null) {
          _recorded.remove(kept);
          state = AsyncData(MonthlyState.failed(_step, SpeakingFailure.silent));
          return;
        }
        _pending.add(_mark(pipeline, task, kept, words, measured));
    }
    if (_index + 1 < _steps.length) {
      _index++;
      state = AsyncData(MonthlyState.task(_step));
      return;
    }
    await _finish();
  }

  /// The tutor's marks, then the measures with them; without marks the
  /// first measures stay.
  Future<MonthlyTaskResult> _mark(
    RecordingPipeline pipeline,
    SpeakingTask task,
    MonthlyTaskResult kept,
    List<TimedWord> words,
    SpeechMetrics measured,
  ) async {
    final marks = await pipeline.mark(
      kept.recordingId,
      SpeakingAnnotateRequest(
        l1: _context.l1,
        l2: _context.l2,
        level: _context.level,
        explainInL1: _context.explainInL1,
        prompt: task.prompt,
        goal: task.goal,
        canDoCodes: task.canDo,
        words: words,
        assessment: true,
      ),
    );
    final annotation = marks.annotated?.annotation;
    final metrics = annotation == null
        ? measured
        : await pipeline.measure(
                kept.recordingId,
                words,
                _context.kit,
                annotation: annotation,
              ) ??
              measured;
    return (
      taskRef: kept.taskRef,
      recordingId: kept.recordingId,
      anchor: kept.anchor,
      metrics: metrics.toJson(),
      clauses: annotation?.clauses.length,
      errorFree: annotation?.clauses.where((c) => c.errorFree).length,
    );
  }

  /// Completes when every recording so far is processed.
  Future<void> processed() => Future.wait(_pending);

  /// Records the task again after the microphone failed.
  void tryAgain() {
    if (state.value is! MonthlyFailed) return;
    state = AsyncData(MonthlyState.task(_step));
  }

  Future<void> _finish() async {
    state = const AsyncData(MonthlyState.finishing());
    final results = await Future.wait(_pending);
    if (!ref.mounted) return;
    final now = ref.read(clockProvider)();
    final monthly = ref.read(monthlyTestRepositoryProvider);
    final previous = {
      for (final task in await monthly.latestBefore(_context.courseId, now))
        task.taskRef: task,
    };
    await _save(results, complete: true);
    if (!ref.mounted) return;
    final titles = {for (final task in _tasks) task.key: task.title};
    state = AsyncData(
      MonthlyState.report(
        baseline: baseline,
        tasks: [
          for (final result in results)
            _reportTask(
              result,
              titles[result.taskRef] ?? result.taskRef,
              result.anchor ? previous[result.taskRef] : null,
            ),
        ],
      ),
    );
  }

  static double? _number(Map<String, Object?>? metrics, String key) =>
      switch (metrics?[key]) {
        final num value => value.toDouble(),
        _ => null,
      };

  static ReportTask _reportTask(
    MonthlyTaskResult result,
    String title,
    MonthlyTaskResult? previous,
  ) {
    final metrics = result.metrics;
    return ReportTask(
      title: title,
      anchor: result.anchor,
      spoken: switch (metrics?['speaking_ms']) {
        final int ms => Duration(milliseconds: ms),
        _ => null,
      },
      words: switch (metrics?['words']) {
        final int words => words,
        _ => null,
      },
      speechRate: _number(metrics, 'speech_rate'),
      longPausesPerMin: _number(metrics, 'long_pauses_per_min'),
      clauses: result.clauses,
      errorFree: result.errorFree,
      previousSpeechRate: _number(previous?.metrics, 'speech_rate'),
      previousLongPausesPerMin: _number(
        previous?.metrics,
        'long_pauses_per_min',
      ),
      previousClauses: previous?.clauses,
      previousErrorFree: previous?.errorFree,
    );
  }

  /// The test and its session, once.
  Future<void> _save(
    List<MonthlyTaskResult> tasks, {
    required bool complete,
  }) async {
    if (_saved || tasks.isEmpty) return;
    _saved = true;
    await ref
        .read(monthlyTestRepositoryProvider)
        .save(
          id: _assessmentId,
          userId: _context.userId,
          courseId: _context.courseId,
          baseline: baseline,
          tasks: tasks,
          complete: complete,
        );
    final startedAt = _startedAt;
    if (startedAt == null) return;
    await ref
        .read(sessionRepositoryProvider)
        .record(
          userId: _context.userId,
          courseId: _context.courseId,
          deviceId: _context.deviceId,
          startedAt: startedAt,
          endedAt: ref.read(clockProvider)(),
          strands: {Strand.output: _speaking},
          planned: {'test': baseline ? 'baseline' : 'monthly'},
          done: {'recordings': tasks.length},
        );
  }

  /// Leaves the test; what was recorded is kept, processing goes on, and
  /// nothing is owed (I-14).
  Future<void> leave() async {
    _limit?.cancel();
    switch (state.value) {
      case MonthlyTask(step: TestStep(recording: true)) ||
          MonthlyMicCheck(listening: true):
        await ref.read(answerRecorderProvider).cancel();
      default:
    }
    if (state.value is MonthlyReport || state.value is MonthlyFinishing) {
      return;
    }
    await _save(_recorded, complete: false);
  }
}
