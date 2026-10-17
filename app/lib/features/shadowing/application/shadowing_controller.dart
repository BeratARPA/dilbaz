import 'dart:async';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/audio/recorder_config.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/card_content_repository.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/data/tasks/shadowing_repository.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/data/tutor/pron_check.dart';
import 'package:dilbaz_app/data/tutor/tutor_providers.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_app/features/shadowing/application/shadowing_state.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shadowing_controller.g.dart';

/// What a shadowing works with, found once.
typedef _Context = ({
  String userId,
  String courseId,
  String deviceId,
  String l1,
  String l2,
  CefrLevel level,
  PackLanguage language,
  Map<String, int> ranks,
  Map<String, PronTag> tags,
});

/// Shadowing (A07, docs/03, ADR-0011): sentences the learner can follow
/// (I-06) are heard and said the same way. Each try is recognized (which
/// words came through) and heard by `tutor/pron_check` (which sounds did
/// not); at most two problems are shown, and the sentence may be tried once
/// more. The learner's recording stays on the device until the sentence is
/// done, to be heard next to the model; then it is removed. Each try is an
/// attempt (I-03); shadowing is no production evidence (I-05).
@riverpod
class ShadowingController extends _$ShadowingController {
  late _Context _context;
  var _sentences = const <SentenceAudio>[];
  var _index = 0;
  Timer? _limit;
  String? _first;
  String? _ownPath;
  final _shown = <String, int>{};
  var _done = 0;
  DateTime? _startedAt;
  Duration _spoken = Duration.zero;
  var _recorded = false;

  /// Where the learner's own try is kept while its sentence is on screen.
  static const _ownId = 'shadowing_try';

  @override
  Future<ShadowingState> build() async {
    // The recorder and the player live as long as the shadowing.
    ref
      ..onDispose(() => _limit?.cancel())
      ..watch(answerRecorderProvider)
      ..watch(clipPlayerProvider);
    final userId = ref.watch(authRepositoryProvider).userId;
    if (userId == null) return const ShadowingState.unavailable();
    final assessments = ref.watch(assessmentRepositoryProvider);
    final content = ref.watch(cardContentRepositoryProvider);
    final tasks = ref.watch(taskContentRepositoryProvider);
    final course = await assessments.course(userId);
    final settings = await ref
        .watch(profileRepositoryProvider)
        .studySettings(userId);
    final language = await content.language();
    if (course == null || settings == null || language == null) {
      return const ShadowingState.unavailable();
    }
    if (!settings.audioConsent) return const ShadowingState.needsConsent();
    final ranks = await tasks.lemmaRanks();
    final knowledge = LemmaKnowledge.fromCards(
      items: await content.items(),
      evidence: await ref.watch(cardRepositoryProvider).evidence(course.id),
      ranks: ranks,
      xlex: await assessments.latestXlex(course.id),
    );
    final sentences = {
      for (final sentence in await content.sentences()) sentence.key: sentence,
    };
    // The dictation's choice: sentences the learner can follow, at their
    // level; shadowing keeps no cards, so every one is new.
    final picked = pickDictations(
      candidates: [
        for (final sentence in sentences.values)
          (key: sentence.key, lemmas: sentence.lemmas, level: sentence.level),
      ],
      coverage: knowledge.coverage,
      level: course.level,
      seed: ref.watch(cardSeedProvider),
      newCount: 5,
    );
    if (picked.isEmpty) return const ShadowingState.nothingToSay();
    _sentences = [for (final key in picked) sentences[key]!];
    _context = (
      userId: userId,
      courseId: course.id,
      deviceId: await ref.watch(deviceRepositoryProvider).deviceId(userId),
      l1: settings.l1,
      l2: course.l2,
      level: course.level,
      language: language,
      ranks: ranks,
      tags: await ref.watch(shadowingRepositoryProvider).pronunciationTags(),
    );
    _startedAt = ref.read(clockProvider)();
    return _sentence(again: false);
  }

  SentenceAudio get _current => _sentences[_index];

  ShadowingState _sentence({required bool again}) => ShadowingState.sentence(
    number: _index + 1,
    total: _sentences.length,
    text: _current.text,
    again: again,
  );

  /// Plays the model sentence.
  Future<void> listen() async {
    final current = state.value;
    if (current is! ShadowingSentence || current.playing || current.recording) {
      return;
    }
    state = AsyncData(current.copyWith(playing: true, audioFailure: null));
    final file = await ref.read(packAudioProvider).file(_current.clip);
    if (!ref.mounted) return;
    var failure = PackFailure.damaged;
    var played = false;
    switch (file) {
      case Err(:final error):
        failure = error;
      case Ok(value: final path):
        played = await ref.read(clipPlayerProvider).play(path);
        if (!ref.mounted) return;
    }
    if (state.value case ShadowingSentence(:final number, :final again)
        when number == current.number && again == current.again) {
      state = AsyncData(
        played
            ? current.copyWith(heard: true)
            : current.copyWith(audioFailure: failure),
      );
    }
  }

  /// Starts saying the sentence; it stops by itself after 15 s.
  Future<void> record() async {
    final current = state.value;
    if (current is! ShadowingSentence || !current.heard || current.recording) {
      return;
    }
    unawaited(ref.read(clipPlayerProvider).stop());
    final started = await ref
        .read(answerRecorderProvider)
        .start(pronunciation: true);
    if (!ref.mounted) return;
    if (started case Err(:final error)) {
      state = AsyncData(
        current.copyWith(
          playing: false,
          failure: error == RecordFailure.permission
              ? SpeakingFailure.permission
              : SpeakingFailure.microphone,
        ),
      );
      return;
    }
    state = AsyncData(
      current.copyWith(playing: false, recording: true, failure: null),
    );
    _limit = Timer(RecorderConfig.shadowingLimit, () => unawaited(stop()));
  }

  /// Stops, then recognizes and hears the try.
  Future<void> stop() async {
    final current = state.value;
    if (current is! ShadowingSentence || !current.recording) return;
    _limit?.cancel();
    final audio = await ref.read(answerRecorderProvider).stop();
    if (!ref.mounted) return;
    if (audio == null) {
      state = AsyncData(
        current.copyWith(recording: false, failure: SpeakingFailure.silent),
      );
      return;
    }
    state = const AsyncData(ShadowingState.checking());
    final (recognized, heard) = await (
      ref.read(speechRepositoryProvider).transcribe(audio),
      ref
          .read(tutorRepositoryProvider)
          .pronCheck(
            PronCheckRequest(
              l1: _context.l1,
              l2: _context.l2,
              level: _context.level,
              reference: _current.text,
              wav: audio.bytes,
            ),
          ),
    ).wait;
    if (!ref.mounted) return;
    final transcript = switch (recognized) {
      Ok(:final value) => value,
      Err() => null,
    };
    final judged = switch (heard) {
      Ok(:final value) => value,
      Err() => null,
    };
    // Recognized, and nothing in it: the sentence again.
    if (transcript != null && transcript.words.isEmpty) {
      state = AsyncData(
        current.copyWith(recording: false, failure: SpeakingFailure.silent),
      );
      return;
    }
    _spoken += audio.duration;
    final check = transcript == null
        ? null
        : DictationCheck.of(
            expected: _current.text,
            typed: transcript.text,
            language: _context.language,
            rankOf: (lemma) => _context.ranks[lemma],
          );
    final found = judged == null || judged.uncertain
        ? const <PronIssue>[]
        : judged.issues;
    final picked = pickPronIssues(
      found,
      severity: {
        for (final MapEntry(:key, :value) in _context.tags.entries)
          key: value.severity,
      },
    );
    final id = await ref
        .read(shadowingRepositoryProvider)
        .recordTry(
          userId: _context.userId,
          courseId: _context.courseId,
          deviceId: _context.deviceId,
          itemRef: _current.key,
          reference: _current.text,
          clip: _current.clip,
          duration: audio.duration,
          at: ref.read(clockProvider)(),
          errorTags: [
            for (final tag in {...found.map((issue) => issue.tag)})
              if (_context.tags.containsKey(tag)) tag,
          ],
          transcript: transcript,
          heard: judged,
          parentAttemptId: _first,
        );
    final store = ref.read(recordingStoreProvider);
    final own = await store.save(_ownId, audio);
    if (!ref.mounted) return;
    _first ??= id;
    _ownPath = own;
    if (!current.again) {
      for (final issue in picked) {
        _shown[issue.tag] = (_shown[issue.tag] ?? 0) + 1;
      }
    }
    state = AsyncData(
      ShadowingState.result(
        number: current.number,
        total: current.total,
        words: check?.words ?? _words(),
        marks: check?.marks,
        issues: [
          for (final issue in picked)
            (
              word: issue.word,
              heard: issue.heard,
              tag: issue.tag,
              about: _context.tags[issue.tag]!.description,
            ),
        ],
        judgement: switch (judged) {
          null => PronJudgement.notHeard,
          HeardPronunciation(uncertain: true) => PronJudgement.uncertain,
          _ => PronJudgement.heard,
        },
        canTryAgain:
            !current.again &&
            (picked.isNotEmpty || (check != null && check.errors > 0)),
        canHearSelf: own != null,
      ),
    );
  }

  /// The sentence's words, when nothing was recognized.
  List<String> _words() => _current.text
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  /// Plays the learner's own try.
  Future<void> hearSelf() async {
    final current = state.value;
    final path = _ownPath;
    if (current is! ShadowingResult || current.playing || path == null) {
      return;
    }
    state = AsyncData(current.copyWith(playing: true));
    await ref.read(clipPlayerProvider).play(path);
    if (!ref.mounted) return;
    if (state.value case final ShadowingResult now) {
      state = AsyncData(now.copyWith(playing: false));
    }
  }

  /// Plays the model sentence next to the learner's try.
  Future<void> hearModel() async {
    final current = state.value;
    if (current is! ShadowingResult || current.playing) return;
    state = AsyncData(current.copyWith(playing: true));
    if (await ref.read(packAudioProvider).file(_current.clip) case Ok(
      value: final path,
    )) {
      if (!ref.mounted) return;
      await ref.read(clipPlayerProvider).play(path);
    }
    if (!ref.mounted) return;
    if (state.value case final ShadowingResult now) {
      state = AsyncData(now.copyWith(playing: false));
    }
  }

  /// Says the sentence once more (A07 step 5).
  Future<void> tryAgain() async {
    if (state.value case ShadowingResult(canTryAgain: true)) {
      await _forgetOwn();
      if (!ref.mounted) return;
      state = AsyncData(
        (_sentence(again: true) as ShadowingSentence).copyWith(heard: true),
      );
    }
  }

  /// On to the next sentence, or the end.
  Future<void> next() async {
    if (state.value is! ShadowingResult) return;
    await _forgetOwn();
    if (!ref.mounted) return;
    _done++;
    _first = null;
    if (_index + 1 < _sentences.length) {
      _index++;
      state = AsyncData(_sentence(again: false));
      return;
    }
    await _record();
    if (!ref.mounted) return;
    state = AsyncData(
      ShadowingState.done(
        sentences: _done,
        shown: Map.unmodifiable(_shown),
        about: {
          for (final tag in _shown.keys) tag: _context.tags[tag]!.description,
        },
      ),
    );
  }

  /// Leaves; what was said is kept, nothing is owed (I-14).
  Future<void> leave() async {
    _limit?.cancel();
    unawaited(ref.read(clipPlayerProvider).stop());
    if (state.value case ShadowingSentence(recording: true)) {
      await ref.read(answerRecorderProvider).cancel();
    }
    if (state.value is ShadowingResult) _done++;
    await _forgetOwn();
    await _record();
  }

  Future<void> _forgetOwn() async {
    final path = _ownPath;
    _ownPath = null;
    unawaited(ref.read(clipPlayerProvider).stop());
    if (path != null) await ref.read(recordingStoreProvider).delete(path);
  }

  /// The session on the fluency strand, once, if a sentence was said.
  Future<void> _record() async {
    final startedAt = _startedAt;
    if (_recorded || _done == 0 || startedAt == null) return;
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
          planned: {'activity': 'shadowing'},
          done: {'sentences': _done},
        );
  }
}
