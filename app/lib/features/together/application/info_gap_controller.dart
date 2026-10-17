import 'dart:async';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/data/tasks/task_content_repository.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/data/together/together_providers.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:dilbaz_app/data/tutor/speaking_annotate_request.dart';
import 'package:dilbaz_app/data/tutor/tutor_providers.dart';
import 'package:dilbaz_app/features/speaking/application/recording_pipeline.dart';
import 'package:dilbaz_app/features/together/application/together_controller.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'info_gap_controller.freezed.dart';
part 'info_gap_controller.g.dart';

/// The learner's own feedback after the task (A15 step 4).
@freezed
sealed class GapFeedback with _$GapFeedback {
  /// Nothing was said into the microphone: nothing to look at.
  const factory nothingSaid() = GapNothingSaid;

  /// The speech is being marked.
  const factory marking() = GapMarking;

  /// At most two corrections (I-02), maybe none.
  const factory corrections(List<SpeechCorrection> corrections) =
      GapCorrections;

  /// The marks could not be had (no consent, quota or connection).
  const factory unavailable() = GapFeedbackUnavailable;
}

/// Where an information gap task is (A15, ADR-0012).
@freezed
sealed class InfoGapState with _$InfoGapState {
  /// No such session or task here.
  const factory unavailable() = InfoGapUnavailable;

  /// The learner started it; the partner has not joined yet.
  const factory waiting({required InfoGapTask task}) = InfoGapWaiting;

  /// The partner started it: join or not now.
  const factory invited({required InfoGapTask task}) = InfoGapInvited;

  /// Both are in: the learner's role, what they chose or marked, and
  /// whether their answer went (the partner's may not have yet).
  const factory playing({
    required InfoGapTask task,
    required String role,
    required GapRole mine,
    required bool chooses,
    String? chosen,
    @Default(<int>{}) Set<int> marked,
    @Default(false) bool answered,
    @Default(false) bool recording,
    @Default(0) int said,
    @Default(false) bool failed,
  }) = InfoGapPlaying;

  /// Both answered: how it went, and the learner's own feedback.
  const factory done({
    required InfoGapTask task,
    required InfoGapCheck check,
    required GapFeedback feedback,
  }) = InfoGapDone;

  /// One of them left it.
  const factory cancelled() = InfoGapCancelled;
}

/// An information gap session on this phone (A15): only the learner's own
/// role is shown, only the learner's own speech is recorded (I-18). The
/// partners' answers meet on the server; the engine checks them against
/// the pack's key (ADR-0012).
@riverpod
class InfoGapController extends _$InfoGapController {
  late ({String userId, String courseId, String deviceId, CefrLevel level})
  _context;
  late ({String l1, String l2, bool explainInL1}) _speech;
  String? _chosen;
  final _marked = <int>{};
  var _recording = false;
  var _failed = false;

  /// The answer went; the session shows it once the server says so.
  var _sent = false;
  final _words = <TimedWord>[];
  var _offsetMs = 0;
  var _said = 0;
  Duration _spoken = Duration.zero;
  DateTime? _joinedAt;
  GapFeedback? _feedback;
  var _filed = false;

  @override
  Future<InfoGapState> build(String sessionId) async {
    ref.watch(answerRecorderProvider);
    final userId = ref.watch(authRepositoryProvider).userId;
    if (userId == null) return const InfoGapState.unavailable();
    final course = await ref.watch(assessmentRepositoryProvider).course(userId);
    final settings = await ref
        .watch(profileRepositoryProvider)
        .studySettings(userId);
    if (course == null || settings == null) {
      return const InfoGapState.unavailable();
    }
    final session = (await ref.watch(pairSessionsProvider.future))
        .where((s) => s.id == sessionId)
        .firstOrNull;
    final task = session == null
        ? null
        : (await ref.watch(taskContentRepositoryProvider).infoGaps())
              .where((t) => t.key == session.taskRef)
              .firstOrNull;
    final role = session?.roles[userId];
    if (session == null || task == null || role == null) {
      return const InfoGapState.unavailable();
    }
    _context = (
      userId: userId,
      courseId: course.id,
      deviceId: await ref.watch(deviceRepositoryProvider).deviceId(userId),
      level: course.level,
    );
    _speech = (
      l1: settings.l1,
      l2: course.l2,
      explainInL1: Scaffolds.forLevel(course.level).explainInL1,
    );
    switch (session.state) {
      case PairState.cancelled:
        return const InfoGapState.cancelled();
      case PairState.invited:
        return session.createdBy == userId
            ? InfoGapState.waiting(task: task)
            : InfoGapState.invited(task: task);
      case PairState.done:
        final check = InfoGapCheck.of(task.answer, {
          for (final MapEntry(:key, :value) in session.roles.entries)
            value: session.answers[key],
        });
        unawaited(Future(() => _finish(session, task, role, check)));
        return InfoGapState.done(
          task: task,
          check: check,
          feedback: _feedback ?? const GapFeedback.marking(),
        );
      case PairState.active:
        _joinedAt ??= ref.read(clockProvider)();
        final chooses = switch (task.answer) {
          ChooseKey(:final chooser) => chooser == role,
          DifferencesKey() => true,
        };
        return InfoGapState.playing(
          task: task,
          role: role,
          mine: role == 'a' ? task.a : task.b,
          chooses: chooses,
          chosen: _chosen,
          marked: {..._marked},
          answered: _sent || session.answers.containsKey(userId),
          recording: _recording,
          said: _said,
          failed: _failed,
        );
    }
  }

  TogetherRepository get _repository => ref.read(togetherRepositoryProvider);

  void _redraw() {
    if (state.value case final InfoGapPlaying playing) {
      state = AsyncData(
        playing.copyWith(
          chosen: _chosen,
          marked: {..._marked},
          recording: _recording,
          said: _said,
          failed: _failed,
          answered: _sent || playing.answered,
        ),
      );
    }
  }

  /// Joins the partner's session.
  Future<void> join() async {
    if (state.value is! InfoGapInvited) return;
    _failed = (await _repository.joinSession(sessionId)) is Err;
  }

  /// Leaves the session; nothing is owed (I-14).
  Future<void> cancel() async {
    if (_recording) await ref.read(answerRecorderProvider).cancel();
    _recording = false;
    final current = state.value;
    if (current is InfoGapDone || current is InfoGapCancelled) return;
    await _repository.cancelSession(sessionId);
  }

  /// Picks option [id] (the role that chooses).
  void choose(String id) {
    if (state.value case InfoGapPlaying(answered: false)) {
      _chosen = id;
      _redraw();
    }
  }

  /// Marks or unmarks line [index] as different.
  void toggle(int index) {
    if (state.value case InfoGapPlaying(answered: false)) {
      if (!_marked.remove(index)) _marked.add(index);
      _redraw();
    }
  }

  /// Sends the learner's answer: the option, the lines marked, or that the
  /// one who was asked is done.
  Future<void> submit() async {
    final current = state.value;
    if (current is! InfoGapPlaying || current.answered) return;
    final Object answer;
    switch (current.task.answer) {
      case ChooseKey() when current.chooses:
        final chosen = _chosen;
        if (chosen == null) return;
        answer = chosen;
      case ChooseKey():
        answer = 'done';
      case DifferencesKey():
        answer = [..._marked]..sort();
    }
    _failed = (await _repository.answerSession(sessionId, answer)) is Err;
    _sent = !_failed;
    _redraw();
  }

  /// Push to talk: records the learner while held (A15 step 2).
  Future<void> startSpeaking() async {
    if (_recording || state.value is! InfoGapPlaying) return;
    _recording = true;
    _redraw();
    final started = await ref.read(answerRecorderProvider).start();
    if (!ref.mounted) return;
    if (started is Err) {
      _recording = false;
      _failed = true;
      _redraw();
    }
  }

  /// Lets go: what was said is written down and kept for the feedback.
  Future<void> stopSpeaking() async {
    if (!_recording) return;
    _recording = false;
    _redraw();
    final audio = await ref.read(answerRecorderProvider).stop();
    if (!ref.mounted || audio == null) return;
    final heard = await ref.read(speechRepositoryProvider).transcribe(audio);
    if (!ref.mounted) return;
    switch (heard) {
      case Ok(:final value):
        // The clips follow each other: their times too.
        for (final word in timedWords(value)) {
          _words.add(
            TimedWord(
              text: word.text,
              startMs: word.startMs + _offsetMs,
              endMs: word.endMs + _offsetMs,
              confidence: word.confidence,
            ),
          );
        }
        _offsetMs += audio.duration.inMilliseconds + 1000;
        _spoken += audio.duration;
        if (value.words.isNotEmpty) _said++;
        _failed = false;
      case Err():
        _failed = true;
    }
    _redraw();
  }

  /// Once both answered: the learner's record, then their own feedback.
  Future<void> _finish(
    PairSession session,
    InfoGapTask task,
    String role,
    InfoGapCheck check,
  ) async {
    if (_filed || !ref.mounted) return;
    _filed = true;
    final now = ref.read(clockProvider)();
    final started = _joinedAt ?? session.createdAt;
    final talked = now.difference(started);
    const cap = Duration(minutes: 30);
    await ref
        .read(sessionRepositoryProvider)
        .record(
          userId: _context.userId,
          courseId: _context.courseId,
          deviceId: _context.deviceId,
          startedAt: started,
          endedAt: now,
          strands: {Strand.output: talked > cap ? cap : talked},
          planned: {'activity': pairTaskActivity, 'task': task.key},
          done: {
            'found': check.found,
            'total': check.total,
            'with_partner': true,
          },
        );
    var feedback = const GapFeedback.nothingSaid();
    Map<String, Object?>? llm;
    if (_words.isNotEmpty) {
      _show(const GapFeedback.marking());
      final marked = await ref
          .read(tutorRepositoryProvider)
          .speakingAnnotate(
            SpeakingAnnotateRequest(
              l1: _speech.l1,
              l2: _speech.l2,
              level: _context.level,
              explainInL1: _speech.explainInL1,
              prompt: task.prompt,
              goal: task.goal,
              words: [..._words],
            ),
          );
      if (!ref.mounted) return;
      switch (marked) {
        case Ok(:final value):
          feedback = GapFeedback.corrections(
            pickCorrections(value.annotation, count: 2),
          );
          llm = value.toJson();
        case Err():
          feedback = const GapFeedback.unavailable();
      }
    }
    await ref
        .read(pairTaskRepositoryProvider)
        .recordTask(
          userId: _context.userId,
          courseId: _context.courseId,
          deviceId: _context.deviceId,
          sessionId: session.id,
          taskRef: task.key,
          role: role,
          answer: session.answers[_context.userId],
          outcome: switch (check.outcome) {
            TaskOutcome.done => 'done',
            TaskOutcome.partial => 'partial',
            TaskOutcome.notDone => 'not_done',
          },
          result: {
            'found': check.found,
            'total': check.total,
            'wrong': check.wrong,
          },
          transcript: _words.map((w) => w.text).join(' '),
          spoken: _spoken,
          at: now,
          llm: llm,
        );
    if (!ref.mounted) return;
    _show(feedback);
  }

  void _show(GapFeedback feedback) {
    _feedback = feedback;
    if (state.value case final InfoGapDone done) {
      state = AsyncData(done.copyWith(feedback: feedback));
    }
  }
}
