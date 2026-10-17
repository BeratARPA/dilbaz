import 'dart:async';
import 'dart:math';

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
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/data/tasks/speaking_task.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/data/tutor/annotated_speech.dart';
import 'package:dilbaz_app/data/tutor/speaking_annotate_request.dart';
import 'package:dilbaz_app/data/tutor/tutor_providers.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_app/features/cards/application/card_session_state.dart'
    show Hint;
import 'package:dilbaz_app/features/speaking/application/recording_pipeline.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'speaking_controller.g.dart';

/// The pipeline of task recordings.
@riverpod
RecordingPipeline recordingPipeline(Ref ref) => RecordingPipeline(
  store: ref.watch(recordingStoreProvider),
  recordings: ref.watch(recordingRepositoryProvider),
  speech: ref.watch(speechRepositoryProvider),
  tutor: ref.watch(tutorRepositoryProvider),
  now: ref.watch(clockProvider),
);

/// What a speaking task works with, found once.
typedef _Context = ({
  String userId,
  String courseId,
  String deviceId,
  String l1,
  String l2,
  CefrLevel level,
  Scaffolds scaffolds,
  bool typed,
  MeasureKit kit,
});

/// One correction being practised: its review and the answers so far.
final class _Practice {
  new(this.correction, this.review);

  final SpeechCorrection correction;
  CardReview review;
  HintLadder? template;
  String? last;
  CorrectionPhase phase = CorrectionPhase.asking;
  final answers = <PracticeAnswer>[];
}

/// A processed recording of this visit, for its attempt.
typedef _Done = ({
  String recordingId,
  String taskRef,
  String prompt,
  Transcript transcript,
  AnnotatedSpeech? annotated,
  TutorFailure? waiting,
  List<_Practice> practice,

  /// The task's attempt, when it was written before: a recording opened
  /// again (docs/08 §5.2).
  String? attemptId,
});

/// A speaking task (A11, docs/03 §A11, docs/09 §5.6): choose, prepare,
/// speak for up to two minutes, then feedback: what went well and three
/// corrections to say again, each with the hint ladder (I-01, I-02).
/// Corrected sentences become the learner's own cards.
@riverpod
class SpeakingController extends _$SpeakingController {
  late _Context _context;
  var _tasks = const <SpeakingTask>[];
  late SpeakingTask _task;
  TaskView? _view;
  Timer? _limit;
  late RecordedAudio _audio;
  String? _recordingId;
  Transcript? _transcript;
  Marks? _marks;
  var _practice = <_Practice>[];
  var _current = 0;
  final _done = <_Done>[];
  var _recorded = false;

  /// The attempt of a recording opened again, written before.
  String? _openedAttempt;

  /// Time spent speaking, and when the feedback of the latest recording
  /// opened: the session's time on output (docs/05 §2).
  DateTime? _startedAt;
  Duration _speaking = Duration.zero;
  Duration _practising = Duration.zero;
  DateTime? _feedbackAt;

  /// Days a task done is not suggested again first.
  static const lately = Duration(days: 14);

  /// Suggestions shown first (I-14: at least two).
  static const suggestions = 3;

  /// How long a feedback that came later waits in the list.
  static const readyFor = Duration(days: 7);

  /// Longest practice time one feedback counts.
  static const _practiceCap = Duration(minutes: 5);

  String _newId() => const Uuid().v7();

  @override
  Future<SpeakingState> build() async {
    ref
      ..onDispose(() => _limit?.cancel())
      ..watch(answerRecorderProvider);
    final userId = ref.watch(authRepositoryProvider).userId;
    if (userId == null) return const SpeakingState.unavailable();
    final course = await ref.watch(assessmentRepositoryProvider).course(userId);
    final settings = await ref
        .watch(profileRepositoryProvider)
        .studySettings(userId);
    final language = await ref.watch(cardContentRepositoryProvider).language();
    final content = ref.watch(taskContentRepositoryProvider);
    if (course == null || settings == null || language == null) {
      return const SpeakingState.unavailable();
    }
    _tasks = [
      for (final task in await content.speakingTasks())
        if (task.anchor == null) task,
    ];
    if (_tasks.isEmpty) return const SpeakingState.unavailable();
    if (!settings.audioConsent) return const SpeakingState.needsConsent();

    _context = (
      userId: userId,
      courseId: course.id,
      deviceId: await ref.watch(deviceRepositoryProvider).deviceId(userId),
      l1: settings.l1,
      l2: course.l2,
      level: course.level,
      scaffolds: Scaffolds.forLevel(course.level),
      typed: settings.silentMode,
      kit: (
        language: language,
        connectors: await content.connectors(),
        ranks: await content.lemmaRanks(),
      ),
    );
    final now = ref.read(clockProvider)();
    final order = suggestTasks(
      tasks: [for (final task in _tasks) (key: task.key, level: task.level)],
      level: course.level,
      seed: ref.watch(cardSeedProvider),
      doneLately: await ref
          .read(recordingRepositoryProvider)
          .taskRefsSince(course.id, now.subtract(lately)),
    );
    final byKey = {for (final task in _tasks) task.key: task};
    final choices = [
      for (final key in order)
        if (byKey[key] case final task?)
          (key: task.key, title: task.title, level: task.level),
    ];
    final waiting = await ref
        .read(recordingRepositoryProvider)
        .readyFeedback(course.id, now.subtract(readyFor));
    return SpeakingState.choosing(
      suggested: choices.take(suggestions).toList(),
      others: choices.skip(suggestions).toList(),
      ready: [
        for (final row in waiting)
          if (byKey[row.taskRef] case final task?)
            (
              recordingId: row.id,
              title: task.title,
              day: startOfLocalDay(row.createdAt),
            ),
      ],
    );
  }

  /// Opens the feedback of an earlier recording whose marks came later
  /// (docs/08 §5.2): the same corrections to practise, hints first (I-01).
  Future<void> openRecording(String id) async {
    if (state.value is! SpeakingChoosing) return;
    final row = await ref.read(recordingRepositoryProvider).recording(id);
    if (!ref.mounted || row == null) return;
    final task = _tasks.where((t) => t.key == row.taskRef).firstOrNull;
    final transcript = row.transcript;
    final annotated = row.annotated;
    if (task == null || transcript == null || annotated == null) return;
    _task = task;
    _view = _taskView(task);
    final now = ref.read(clockProvider)();
    _startedAt ??= now;
    _recordingId = id;
    _openedAttempt = row.attemptId;
    _transcript = transcript;
    _marks = (annotated: annotated, waiting: null);
    _practice = [
      for (final correction in pickCorrections(annotated.annotation))
        _Practice(correction, _context.scaffolds.review()),
    ];
    _current = 0;
    _feedbackAt = now;
    _emit();
  }

  TaskView _taskView(SpeakingTask task) => TaskView(
    key: task.key,
    title: task.title,
    prompt: task.prompt,
    preparation: _context.scaffolds.taskPreparation,
    limit: RecorderConfig.taskLimit,
    phrases: [
      for (final (i, phrase) in task.phrases.indexed)
        (
          phrase: phrase,
          meaning: i < task.phraseMeanings.length ? task.phraseMeanings[i] : '',
        ),
    ],
    phrasesOpen: _context.scaffolds.taskPhrases,
  );

  /// Opens the card of task [key].
  void choose(String key) {
    final task = _tasks.where((t) => t.key == key).firstOrNull;
    if (task == null) return;
    _task = task;
    _view = _taskView(task);
    _startedAt ??= ref.read(clockProvider)();
    state = AsyncData(SpeakingState.preparing(_view!));
  }

  /// Back to the list, before speaking.
  void chooseAgain() {
    if (state.value is! SpeakingPreparing) return;
    ref.invalidateSelf();
  }

  /// Starts the recording; it stops by itself at the task's limit.
  Future<void> startRecording() async {
    final view = _view;
    if (view == null || state.value is! SpeakingPreparing) return;
    final started = await ref.read(answerRecorderProvider).start();
    if (!ref.mounted) return;
    if (started case Err(:final error)) {
      state = AsyncData(
        SpeakingState.failed(
          view,
          error == RecordFailure.permission
              ? SpeakingFailure.permission
              : SpeakingFailure.microphone,
        ),
      );
      return;
    }
    state = AsyncData(SpeakingState.recording(view));
    _limit = Timer(view.limit, () => unawaited(stopRecording()));
  }

  /// Stops the recording, keeps it and processes it.
  Future<void> stopRecording() async {
    final view = _view;
    if (view == null || state.value is! SpeakingRecording) return;
    _limit?.cancel();
    final audio = await ref.read(answerRecorderProvider).stop();
    if (!ref.mounted) return;
    if (audio == null) {
      state = AsyncData(SpeakingState.failed(view, SpeakingFailure.silent));
      return;
    }
    _audio = audio;
    _speaking += audio.duration;
    final id = _newId();
    _recordingId = id;
    await ref
        .read(recordingPipelineProvider)
        .keep(
          id: id,
          userId: _context.userId,
          courseId: _context.courseId,
          taskRef: view.key,
          audio: audio,
        );
    await _process();
  }

  /// Tries the kept recording again after a failure.
  Future<void> retry() async {
    if (state.value case SpeakingFailed(canRetry: true)) await _process();
  }

  /// Back to the task card for a new recording after a failure.
  void tryAgain() {
    final view = _view;
    if (view == null || state.value is! SpeakingFailed) return;
    state = AsyncData(SpeakingState.preparing(view));
  }

  Future<void> _process() async {
    final view = _view!;
    final audio = _audio;
    final id = _recordingId!;
    final pipeline = ref.read(recordingPipelineProvider);
    state = AsyncData(
      SpeakingState.processing(view, ProcessingStep.transcribing),
    );
    final heard = await pipeline.transcribe(id, audio);
    if (!ref.mounted) return;
    final Transcript transcript;
    switch (heard) {
      case Ok(:final value):
        transcript = value;
      case Err(:final error):
        state = AsyncData(
          SpeakingState.failed(
            view,
            error == SpeechFailure.network
                ? SpeakingFailure.network
                : SpeakingFailure.speech,
            canRetry: true,
          ),
        );
        return;
    }
    final words = timedWords(transcript);
    final silent =
        SpeechMetrics.of(words, language: _context.kit.language) == null;
    if (silent) {
      state = AsyncData(SpeakingState.failed(view, SpeakingFailure.silent));
      return;
    }
    _transcript = transcript;
    state = AsyncData(SpeakingState.processing(view, ProcessingStep.marking));
    final task = _task;
    final marks = await pipeline.mark(
      id,
      SpeakingAnnotateRequest(
        l1: _context.l1,
        l2: _context.l2,
        level: _context.level,
        explainInL1: _context.scaffolds.explainInL1,
        prompt: task.prompt,
        goal: task.goal,
        canDoCodes: task.canDo,
        words: words,
      ),
    );
    if (!ref.mounted) return;
    _marks = marks;
    await pipeline.measure(
      id,
      words,
      _context.kit,
      annotation: marks.annotated?.annotation,
    );
    if (!ref.mounted) return;
    final annotation = marks.annotated?.annotation;
    _practice = [
      if (annotation != null)
        for (final correction in pickCorrections(annotation))
          _Practice(correction, _context.scaffolds.review()),
    ];
    _current = 0;
    _feedbackAt = ref.read(clockProvider)();
    _emit();
  }

  /// The correction being practised, while it waits for an answer.
  _Practice? get _asking {
    if (state.value is! SpeakingFeedback || _current >= _practice.length) {
      return null;
    }
    final practice = _practice[_current];
    return practice.phase == CorrectionPhase.asking ? practice : null;
  }

  /// Starts saying the current correction again.
  Future<void> startSaying() async {
    final practice = _asking;
    if (practice == null) return;
    // Listening from the press, so that letting go before the microphone
    // opened stops it too, as on a card.
    practice.phase = CorrectionPhase.listening;
    _emit();
    final recorder = ref.read(answerRecorderProvider);
    final started = await recorder.start();
    if (!ref.mounted) return;
    if (started is Err) {
      practice.phase = CorrectionPhase.asking;
      _emit();
      return;
    }
    // Let go before the microphone opened, and already checked: nothing to
    // keep.
    if (practice.phase != CorrectionPhase.listening) {
      await recorder.cancel();
      return;
    }
    _limit = Timer(RecorderConfig.cardLimit, () => unawaited(stopSaying()));
  }

  /// Stops and checks what was said.
  Future<void> stopSaying() async {
    if (_current >= _practice.length) return;
    final practice = _practice[_current];
    if (practice.phase != CorrectionPhase.listening) return;
    _limit?.cancel();
    final audio = await ref.read(answerRecorderProvider).stop();
    if (!ref.mounted) return;
    if (audio == null) {
      practice.phase = CorrectionPhase.asking;
      _emit();
      return;
    }
    practice.phase = CorrectionPhase.checking;
    _emit();
    final heard = await ref.read(speechRepositoryProvider).transcribe(audio);
    if (!ref.mounted) return;
    switch (heard) {
      case Ok(:final value):
        _judge(practice, value.text, heard: true);
      case Err():
        practice.phase = CorrectionPhase.asking;
        _emit();
    }
  }

  /// Checks a typed answer of the current correction.
  void submit(String text) {
    final practice = _asking;
    if (practice == null || text.trim().isEmpty) return;
    _judge(practice, text, heard: false);
  }

  /// The answer counts when it is the corrected sentence (after
  /// normalization): practice is for the fix itself, so a small slip is a
  /// miss here. The alignment still gives the template hints.
  void _judge(_Practice practice, String text, {required bool heard}) {
    final checker = AnswerChecker(_context.kit.language);
    final key = AnswerKey(
      reference: practice.correction.corrected,
      targetLemmas: const {},
    );
    practice.last = text;
    final matched = checker.match(text, key);
    if (matched?.verdict == Verdict.unintelligible) {
      practice.phase = CorrectionPhase.asking;
      _emit();
      return;
    }
    final evaluation =
        matched ?? const Evaluation(verdict: Verdict.wrong, targetOk: false);
    if (matched == null) {
      practice.template =
          checker.checkWithoutLlm(text, key).ladder ?? practice.template;
    }
    practice.answers.add((
      text: text,
      heard: heard,
      verdict: evaluation.verdict,
      hintsUsed: practice.review.hintLevel,
      at: ref.read(clockProvider)(),
    ));
    practice
      ..review = practice.review.answer(evaluation, latencyMs: 0)
      ..phase = _phaseOf(practice.review);
    _emit();
  }

  static CorrectionPhase _phaseOf(CardReview review) => switch (review) {
    CardReview(outcome: Recalled()) => CorrectionPhase.recalled,
    CardReview(isDone: true) => CorrectionPhase.shown,
    _ => CorrectionPhase.asking,
  };

  /// Opens the next hint after a try.
  void nextHint() {
    final practice = _asking;
    if (practice == null || !_canHint(practice)) return;
    practice.review = practice.review.nextHint();
    _emit();
  }

  /// Opens the corrected sentence after a try (I-01).
  void reveal() {
    final practice = _asking;
    if (practice == null || !_canReveal(practice)) return;
    practice
      ..review = practice.review.reveal()
      ..phase = CorrectionPhase.shown;
    _emit();
  }

  /// On to the next correction.
  void nextCorrection() {
    if (_current >= _practice.length) return;
    final phase = _practice[_current].phase;
    if (phase != CorrectionPhase.recalled && phase != CorrectionPhase.shown) {
      return;
    }
    _current++;
    _emit();
  }

  /// The task once more (docs/03 A11 step 4c): this recording is kept.
  Future<void> redo() async {
    final view = _view;
    if (view == null || state.value is! SpeakingFeedback) return;
    _closeFeedback();
    state = AsyncData(SpeakingState.preparing(view));
  }

  /// Ends the task: the attempts, the cards and the session are written.
  Future<void> finish() async {
    if (state.value is! SpeakingFeedback) return;
    final cards = await _record();
    if (!ref.mounted) return;
    state = AsyncData(SpeakingState.done(cards: cards));
  }

  /// Leaves the task; what was done is kept, nothing is owed (I-14).
  Future<void> leave() async {
    _limit?.cancel();
    final listening =
        state.value is SpeakingRecording ||
        (_current < _practice.length &&
            _practice[_current].phase == CorrectionPhase.listening);
    if (listening) await ref.read(answerRecorderProvider).cancel();
    await _record();
  }

  /// Files the latest recording's feedback for its attempt.
  void _closeFeedback() {
    final id = _recordingId;
    final transcript = _transcript;
    final at = _feedbackAt;
    if (id == null || transcript == null) return;
    if (at != null) {
      final spent = ref.read(clockProvider)().difference(at);
      _practising += spent > _practiceCap ? _practiceCap : spent;
    }
    _done.add((
      recordingId: id,
      taskRef: _task.key,
      prompt: _task.prompt,
      transcript: transcript,
      annotated: _marks?.annotated,
      waiting: _marks?.waiting,
      practice: _practice,
      attemptId: _openedAttempt,
    ));
    _openedAttempt = null;
    _recordingId = null;
    _transcript = null;
    _marks = null;
    _practice = [];
    _feedbackAt = null;
  }

  /// Writes the attempts, the corrected sentences as cards and the session,
  /// once; returns how many cards were added.
  Future<int> _record() async {
    if (_recorded) return 0;
    _recorded = true;
    if (state.value is SpeakingFeedback) _closeFeedback();
    final startedAt = _startedAt;
    if (_done.isEmpty || startedAt == null) return 0;
    final recordings = ref.read(recordingRepositoryProvider);
    final now = ref.read(clockProvider)();
    for (final done in _done) {
      final attemptId =
          done.attemptId ??
          await recordings.recordAttempt(
            userId: _context.userId,
            courseId: _context.courseId,
            deviceId: _context.deviceId,
            recordingId: done.recordingId,
            taskRef: done.taskRef,
            prompt: done.prompt,
            at: now,
            transcript: done.transcript,
            annotated: done.annotated,
            llmCode: done.waiting?.name,
          );
      for (final practice in done.practice) {
        if (practice.answers.isEmpty) continue;
        await recordings.recordPractice(
          userId: _context.userId,
          courseId: _context.courseId,
          deviceId: _context.deviceId,
          parentAttemptId: attemptId,
          taskRef: done.taskRef,
          correction: practice.correction,
          answers: practice.answers,
        );
      }
    }
    final language = _context.kit.language;
    final sentences = <String, CorrectedSentence>{};
    for (final done in _done) {
      for (final practice in done.practice) {
        final correction = practice.correction;
        final meaning = correction.meaningL1?.trim() ?? '';
        if (meaning.isEmpty) continue;
        sentences[language.normalize(correction.corrected)] = (
          sentence: correction.corrected,
          meaning: meaning,
          lemmas: [
            ...{
              for (final word in language.tokenize(correction.corrected))
                ...language.lemmasOf(word),
            },
          ],
        );
      }
    }
    final added = sentences.isEmpty
        ? const <String>[]
        : await recordings.addCorrections(
            userId: _context.userId,
            courseId: _context.courseId,
            sentences: sentences.values.toList(),
          );
    await ref
        .read(sessionRepositoryProvider)
        .record(
          userId: _context.userId,
          courseId: _context.courseId,
          deviceId: _context.deviceId,
          startedAt: startedAt,
          endedAt: now,
          strands: {Strand.output: _speaking + _practising},
          planned: {'task': _done.first.taskRef},
          done: {'recordings': _done.length, 'cards': added.length},
        );
    return added.length;
  }

  /// Hint [level] (1–3): the tutor's words, else the template.
  static Hint? _hint(_Practice practice, int level) {
    final ladder = practice.correction.ladder;
    final written = switch (level) {
      1 => ladder.h1,
      2 => ladder.h2,
      _ => ladder.h3,
    };
    if (written.trim().isNotEmpty) return Hint.written(written.trim());
    final template = practice.template;
    if (template == null) return null;
    return switch (level) {
      1 => Hint.kind(template.kind),
      2 when template.place != null => Hint.place(template.place!),
      _ => null,
    };
  }

  static bool _canHint(_Practice practice) {
    final level = practice.review.hintLevel;
    return !practice.review.isDone &&
        level > 0 &&
        level < CardReview.answerLevel - 1 &&
        _hint(practice, level + 1) != null;
  }

  static bool _canReveal(_Practice practice) =>
      !practice.review.isDone && practice.review.misses > 0;

  CorrectionView _correctionView(_Practice practice) {
    final level = min(practice.review.hintLevel, CardReview.answerLevel - 1);
    final ended =
        practice.phase == CorrectionPhase.recalled ||
        practice.phase == CorrectionPhase.shown;
    return CorrectionView(
      original: practice.correction.original,
      phase: practice.phase,
      hints: [for (var i = 1; i <= level; i++) ?_hint(practice, i)],
      last: practice.last,
      corrected: ended ? practice.correction.corrected : null,
      canHint: practice.phase == CorrectionPhase.asking && _canHint(practice),
      canReveal:
          practice.phase == CorrectionPhase.asking && _canReveal(practice),
    );
  }

  void _emit() {
    final view = _view;
    final transcript = _transcript;
    if (view == null || transcript == null || !ref.mounted) return;
    final words = timedWords(transcript);
    final metrics = SpeechMetrics.of(
      words,
      language: _context.kit.language,
      annotation: _marks?.annotated?.annotation,
    );
    state = AsyncData(
      SpeakingState.feedback(
        FeedbackView(
          task: view,
          transcript: transcript.text,
          spoken: Duration(milliseconds: metrics?.speakingMs ?? 0),
          words: metrics?.words ?? 0,
          strengths: _marks?.annotated?.annotation.strengths ?? const [],
          waiting: _marks?.waiting,
          corrections: [
            for (final practice in _practice) _correctionView(practice),
          ],
          current: _current,
          typed: _context.typed,
        ),
      ),
    );
  }
}
