import 'dart:async';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/attempt_draft.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/card_content_repository.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_app/features/dictation_practice/application/dictation_practice_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dictation_practice_controller.g.dart';

/// The pair catalog's perception tags (`perc.*`) by the mark they name;
/// the other marks have no tag of their own yet.
const Map<DictationMark, String> perceptionTags = {
  DictationMark.ending: 'perc.endings',
  DictationMark.weakForm: 'perc.weak_forms',
};

/// What a dictation works with, found once.
typedef _Context = ({
  String userId,
  String courseId,
  String deviceId,
  PackLanguage language,
  Map<String, int> ranks,
});

/// Dictation (A05, docs/03): sentences the learner can understand (I-06)
/// are heard and written down; each is checked word by word, the misses
/// sorted into kinds (`perc.*`), and may be heard slowly and written once
/// more. Each sentence is a dictation card: its first try rates it
/// (FSRS); every try is an attempt (I-03). No LLM.
@riverpod
class DictationPracticeController extends _$DictationPracticeController {
  late _Context _context;
  var _sentences = const <SentenceAudio>[];
  var _cards = const <String, StoredCard>{};
  var _index = 0;
  var _plays = 0;
  final _tries = <AttemptDraft>[];
  DictationCheck? _first;
  var _heardRight = 0;
  final _misses = <DictationMark, int>{};
  var _done = 0;
  DateTime? _startedAt;
  var _recorded = false;
  final _scheduler = SrsScheduler();

  @override
  Future<DictationPracticeState> build() async {
    // The player lives as long as the dictation.
    ref.watch(clipPlayerProvider);
    final userId = ref.watch(authRepositoryProvider).userId;
    if (userId == null) return const DictationPracticeState.unavailable();
    final assessments = ref.watch(assessmentRepositoryProvider);
    final content = ref.watch(cardContentRepositoryProvider);
    final cards = ref.watch(cardRepositoryProvider);
    final tasks = ref.watch(taskContentRepositoryProvider);
    final seed = ref.watch(cardSeedProvider);
    final now = ref.watch(clockProvider)();
    final course = await assessments.course(userId);
    final language = await content.language();
    if (course == null || language == null) {
      return const DictationPracticeState.unavailable();
    }
    final ranks = await tasks.lemmaRanks();
    final knowledge = LemmaKnowledge.fromCards(
      items: await content.items(),
      evidence: await cards.evidence(course.id),
      ranks: ranks,
      xlex: await assessments.latestXlex(course.id),
    );
    final sentences = {
      for (final sentence in await content.sentences()) sentence.key: sentence,
    };
    _cards = {
      for (final card in await cards.cards(course.id))
        if (card.mode == CardMode.dictation) card.itemRef: card,
    };
    final due = [
      for (final card in _cards.values)
        if (!card.memory.due.isAfter(now)) card,
    ]..sort((a, b) => a.memory.due.compareTo(b.memory.due));
    final picked = pickDictations(
      candidates: [
        for (final sentence in sentences.values)
          (key: sentence.key, lemmas: sentence.lemmas, level: sentence.level),
      ],
      coverage: knowledge.coverage,
      level: course.level,
      seed: seed,
      due: [for (final card in due) card.itemRef],
      carded: _cards.keys.toSet(),
    );
    if (picked.isEmpty) return const DictationPracticeState.nothingToHear();
    _sentences = [for (final key in picked) sentences[key]!];
    _context = (
      userId: userId,
      courseId: course.id,
      deviceId: await ref.watch(deviceRepositoryProvider).deviceId(userId),
      language: language,
      ranks: ranks,
    );
    _startedAt = now;
    return _listening(slow: false);
  }

  SentenceAudio get _sentence => _sentences[_index];

  DictationPracticeState _listening({required bool slow}) {
    _plays = 0;
    return DictationPracticeState.listening(
      number: _index + 1,
      total: _sentences.length,
      slow: slow,
    );
  }

  /// Plays the sentence, slowly on the second try.
  Future<void> listen() async {
    final current = state.value;
    if (current is! DictationListening || current.playing) return;
    state = AsyncData(current.copyWith(playing: true, failure: null));
    final clip = current.slow
        ? _sentence.slowClip ?? _sentence.clip
        : _sentence.clip;
    final file = await ref.read(packAudioProvider).file(clip);
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
    if (played) _plays++;
    // The learner may have gone on while the clip played.
    if (state.value case DictationListening(:final number)
        when number == current.number) {
      state = AsyncData(
        played
            ? current.copyWith(heard: true)
            : current.copyWith(failure: failure),
      );
    }
  }

  /// Checks what was written for the sentence on screen.
  void check(String typed) {
    final current = state.value;
    if (current is! DictationListening ||
        !current.heard ||
        typed.trim().isEmpty) {
      return;
    }
    unawaited(ref.read(clipPlayerProvider).stop());
    final result = DictationCheck.of(
      expected: _sentence.text,
      typed: typed,
      language: _context.language,
      rankOf: (lemma) => _context.ranks[lemma],
    );
    _first ??= result;
    _tries.add(
      AttemptDraft(
        activity: 'dictation',
        prompt: {
          'reference': _sentence.text,
          'clip': current.slow ? _sentence.slowClip : _sentence.clip,
        },
        response: {
          'text': typed,
          'source': 'typed',
          'plays': _plays,
          'slow': current.slow,
        },
        createdAtClient: ref.read(clockProvider)(),
        verdict: result.errors == 0 ? 'correct' : 'wrong',
        errorTags: [
          for (final mark in {...result.marks}) ?perceptionTags[mark],
        ],
      ),
    );
    state = AsyncData(
      DictationPracticeState.checked(
        number: current.number,
        total: current.total,
        result: (
          words: result.words,
          marks: result.marks,
          extra: result.extra,
          typed: typed,
          errors: result.errors,
        ),
        canTryAgain:
            !current.slow && result.errors > 0 && _sentence.slowClip != null,
      ),
    );
  }

  /// Hears the sentence slowly and writes it once more (A05 step 5).
  void tryAgainSlowly() {
    if (state.value case DictationChecked(canTryAgain: true)) {
      state = AsyncData(_listening(slow: true));
    }
  }

  /// Files the sentence and goes on to the next, or ends.
  Future<void> next() async {
    if (state.value is! DictationChecked) return;
    await _file();
    if (!ref.mounted) return;
    if (_index + 1 < _sentences.length) {
      _index++;
      state = AsyncData(_listening(slow: false));
      return;
    }
    await _record();
    if (!ref.mounted) return;
    state = AsyncData(
      DictationPracticeState.done(
        sentences: _done,
        heardRight: _heardRight,
        misses: Map.unmodifiable(_misses),
      ),
    );
  }

  /// Leaves; what was written is kept, nothing is owed (I-14).
  Future<void> leave() async {
    unawaited(ref.read(clipPlayerProvider).stop());
    if (state.value is DictationChecked) await _file();
    await _record();
  }

  /// The sentence's card, rated by its first try, and every try as an
  /// attempt, once.
  Future<void> _file() async {
    final first = _first;
    if (first == null || _tries.isEmpty) return;
    final cards = ref.read(cardRepositoryProvider);
    final card =
        _cards[_sentence.key] ??
        await cards.introduce(
          userId: _context.userId,
          courseId: _context.courseId,
          itemRef: _sentence.key,
          mode: CardMode.dictation,
        );
    final rating = first.rating();
    await cards.recordReview(
      userId: _context.userId,
      courseId: _context.courseId,
      deviceId: _context.deviceId,
      card: card,
      attempts: List.of(_tries),
      rating: rating,
      after: _scheduler.review(
        card.memory,
        rating,
        at: ref.read(clockProvider)(),
      ),
    );
    _done++;
    if (first.errors == 0) _heardRight++;
    for (final mark in first.marks) {
      if (mark == DictationMark.heard || mark == DictationMark.slip) continue;
      _misses[mark] = (_misses[mark] ?? 0) + 1;
    }
    if (first.extra.isNotEmpty) {
      _misses[DictationMark.changed] =
          (_misses[DictationMark.changed] ?? 0) + first.extra.length;
    }
    _tries.clear();
    _first = null;
  }

  /// The session on the language strand, once, if a sentence was written.
  Future<void> _record() async {
    final startedAt = _startedAt;
    if (_recorded || _done == 0 || startedAt == null) return;
    _recorded = true;
    final now = ref.read(clockProvider)();
    await ref
        .read(sessionRepositoryProvider)
        .record(
          userId: _context.userId,
          courseId: _context.courseId,
          deviceId: _context.deviceId,
          startedAt: startedAt,
          endedAt: now,
          strands: {Strand.language: now.difference(startedAt)},
          planned: {'activity': 'dictation'},
          done: {'sentences': _done},
        );
  }
}
