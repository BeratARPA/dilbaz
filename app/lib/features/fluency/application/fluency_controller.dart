import 'dart:async';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/data/tasks/speaking_task.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/features/fluency/application/fluency_state.dart';
import 'package:dilbaz_app/features/speaking/application/recording_pipeline.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'fluency_controller.g.dart';

/// What a 4/3/2 works with, found once.
typedef _Context = ({
  String userId,
  String courseId,
  String deviceId,
  MeasureKit kit,
});

/// 4/3/2 (A12, docs/03, docs/09 §5.7): a topic already spoken about, told
/// three times in less time each round. Each round shows its words a
/// minute and long pauses a minute; nothing is corrected. Each round is an
/// attempt (I-03); the audio is not kept.
@riverpod
class FluencyController extends _$FluencyController {
  late _Context _context;
  var _tasks = const <String, SpeakingTask>{};
  var _rounds = const <Duration>[];
  late SpeakingTask _task;
  final _results = <RoundResult>[];
  String? _firstAttempt;
  Timer? _limit;
  DateTime? _startedAt;
  Duration _spoken = Duration.zero;
  var _recorded = false;

  /// A 4/3/2 on a topic told this lately goes after the others.
  static const lately = Duration(days: 7);

  @override
  Future<FluencyState> build() async {
    ref
      ..onDispose(() => _limit?.cancel())
      ..watch(answerRecorderProvider);
    final userId = ref.watch(authRepositoryProvider).userId;
    if (userId == null) return const FluencyState.unavailable();
    final course = await ref.watch(assessmentRepositoryProvider).course(userId);
    final settings = await ref
        .watch(profileRepositoryProvider)
        .studySettings(userId);
    final language = await ref.watch(cardContentRepositoryProvider).language();
    final content = ref.watch(taskContentRepositoryProvider);
    if (course == null || settings == null || language == null) {
      return const FluencyState.unavailable();
    }
    if (!settings.audioConsent) return const FluencyState.needsConsent();
    _tasks = {
      for (final task in await content.speakingTasks())
        if (task.anchor == null) task.key: task,
    };
    final now = ref.read(clockProvider)();
    // The tasks spoken about: a practice recording with speech in it.
    final spoken = <String, DateTime>{};
    for (final row
        in await ref.read(recordingRepositoryProvider).recordings(course.id)) {
      final key = row.taskRef;
      if (row.isAssessment ||
          key == null ||
          !_tasks.containsKey(key) ||
          row.timedWords == null ||
          !row.hasSpeech) {
        continue;
      }
      final last = spoken[key];
      if (last == null || row.createdAt.isAfter(last)) {
        spoken[key] = row.createdAt;
      }
    }
    if (spoken.isEmpty) return const FluencyState.noTopic();
    final order = fluencyTopics(
      spoken: [
        for (final MapEntry(:key, :value) in spoken.entries)
          (key: key, lastSpoken: value),
      ],
      toldLately: await ref
          .read(fluencyRepositoryProvider)
          .toldSince(course.id, now.subtract(lately)),
    );
    _rounds = fluencyRounds(course.level);
    _context = (
      userId: userId,
      courseId: course.id,
      deviceId: await ref.watch(deviceRepositoryProvider).deviceId(userId),
      kit: (
        language: language,
        connectors: await content.connectors(),
        ranks: await content.lemmaRanks(),
      ),
    );
    return FluencyState.choosing(
      topics: [for (final key in order) (key: key, title: _tasks[key]!.title)],
      rounds: _rounds,
    );
  }

  int get _number => _results.length + 1;

  TaskView _view() => TaskView(
    key: _task.key,
    title: _task.title,
    prompt: _task.prompt,
    // A known topic: no time to prepare, no phrases.
    preparation: Duration.zero,
    limit: _rounds[_results.length],
  );

  /// Takes topic [key]: the first round's card.
  void choose(String key) {
    final task = _tasks[key];
    if (task == null || state.value is! FluencyChoosing) return;
    _task = task;
    _startedAt ??= ref.read(clockProvider)();
    state = AsyncData(
      FluencyState.round(task: _view(), number: 1, recording: false),
    );
  }

  /// On to the next round, from between rounds or after a failure.
  void nextRound() {
    final ready = switch (state.value) {
      FluencyBetween() || FluencyFailed() => true,
      _ => false,
    };
    if (!ready) return;
    state = AsyncData(
      FluencyState.round(task: _view(), number: _number, recording: false),
    );
  }

  /// Starts the round; it stops by itself at its time.
  Future<void> startRound() async {
    if (state.value case FluencyRound(recording: false)) {
      final started = await ref.read(answerRecorderProvider).start();
      if (!ref.mounted) return;
      if (started case Err(:final error)) {
        state = AsyncData(
          FluencyState.failed(
            number: _number,
            failure: error == RecordFailure.permission
                ? SpeakingFailure.permission
                : SpeakingFailure.microphone,
          ),
        );
        return;
      }
      state = AsyncData(
        FluencyState.round(task: _view(), number: _number, recording: true),
      );
      _limit = Timer(_view().limit, () => unawaited(stopRound()));
    }
  }

  /// Stops the round, writes it down and measures it.
  Future<void> stopRound() async {
    if (state.value case FluencyRound(recording: true)) {
      _limit?.cancel();
      final limit = _view().limit;
      final audio = await ref.read(answerRecorderProvider).stop();
      if (!ref.mounted) return;
      if (audio == null) {
        state = AsyncData(
          FluencyState.failed(number: _number, failure: SpeakingFailure.silent),
        );
        return;
      }
      _spoken += audio.duration;
      state = const AsyncData(FluencyState.checking());
      final heard = await ref.read(speechRepositoryProvider).transcribe(audio);
      if (!ref.mounted) return;
      final transcript = switch (heard) {
        Ok(:final value) => value,
        Err() => null,
      };
      final metrics = transcript == null ? null : _measure(transcript);
      // Written down, but nothing heard in it: the round again.
      if (transcript != null && metrics == null) {
        state = AsyncData(
          FluencyState.failed(number: _number, failure: SpeakingFailure.silent),
        );
        return;
      }
      final id = await ref
          .read(fluencyRepositoryProvider)
          .recordRound(
            userId: _context.userId,
            courseId: _context.courseId,
            deviceId: _context.deviceId,
            taskRef: _task.key,
            round: _number,
            limit: limit,
            duration: audio.duration,
            at: ref.read(clockProvider)(),
            transcript: transcript,
            metrics: metrics,
            parentAttemptId: _firstAttempt,
          );
      if (!ref.mounted) return;
      _firstAttempt ??= id;
      _results.add((
        number: _number,
        limit: limit,
        spoken: audio.duration,
        words: metrics?.words,
        speechRate: metrics?.speechRate,
        longPausesPerMin: metrics?.longPausesPerMin,
      ));
      if (_results.length < _rounds.length) {
        state = AsyncData(
          FluencyState.between(
            results: List.unmodifiable(_results),
            next: _rounds[_results.length],
          ),
        );
        return;
      }
      await _record();
      if (!ref.mounted) return;
      state = AsyncData(
        FluencyState.done(results: List.unmodifiable(_results)),
      );
    }
  }

  SpeechMetrics? _measure(Transcript transcript) => SpeechMetrics.of(
    timedWords(transcript),
    language: _context.kit.language,
    connectors: _context.kit.connectors,
    rankOf: (lemma) => _context.kit.ranks[lemma],
  );

  /// Leaves; what was said is kept, nothing is owed (I-14).
  Future<void> leave() async {
    _limit?.cancel();
    if (state.value case FluencyRound(recording: true)) {
      await ref.read(answerRecorderProvider).cancel();
    }
    await _record();
  }

  /// The session on the fluency strand, once, if a round was said.
  Future<void> _record() async {
    final startedAt = _startedAt;
    if (_recorded || _results.isEmpty || startedAt == null) return;
    _recorded = true;
    await ref
        .read(sessionRepositoryProvider)
        .record(
          userId: _context.userId,
          courseId: _context.courseId,
          deviceId: _context.deviceId,
          startedAt: startedAt,
          endedAt: ref.read(clockProvider)(),
          strands: {Strand.fluency: _spoken},
          planned: {'activity': 'fluency_432', 'task': _task.key},
          done: {'rounds': _results.length},
        );
  }
}
