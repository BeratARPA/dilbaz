import 'dart:async';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/assessment_repository.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/placement_bank.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/features/placement/application/placement_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'placement_controller.g.dart';

/// Seed of a test's random choices: the order of the words, the questions
/// drawn and the order of their choices. Tests fix it.
@riverpod
int placementSeed(Ref ref) =>
    DateTime.now().microsecondsSinceEpoch & 0x3FFFFFFF;

/// The placement test (A24, docs/06-assessment.md §2): vocabulary, grammar
/// and dictation, each optional after the first. Nothing is shown as right
/// or wrong along the way; the parts that were finished are saved as one
/// assessment, with the level estimates they lead to.
@riverpod
class PlacementController extends _$PlacementController {
  /// Times a dictation sentence may be played.
  static const plays = 2;

  late String _userId;
  late StudiedCourse _course;
  late PlacementBank _bank;
  late int _seed;
  late SeededRandom _random;
  late List<PlacementPart> _parts;
  late List<XlexWord> _words;
  var _known = <bool>[];
  Staircase<GrammarQuestion>? _staircase;
  var _choices = <String?>[];
  var _written = <({String typed, int plays, DictationScore score})>[];
  var _finished = <PlacementPart>{};
  var _left = <PlacementPart>{};
  var _durations = <PlacementPart, int>{};
  final _watch = Stopwatch();

  @override
  Future<PlacementState> build() async {
    // The player lives as long as the test: one only read is disposed at
    // once, before its clip plays.
    ref.watch(clipPlayerProvider);
    final userId = ref.watch(authRepositoryProvider).userId;
    final assessments = ref.watch(assessmentRepositoryProvider);
    final bankRepository = ref.watch(placementBankRepositoryProvider);
    final seed = ref.watch(placementSeedProvider);
    final course = userId == null ? null : await assessments.course(userId);
    if (userId == null || course == null) {
      return const PlacementState.unavailable();
    }
    final bank = await bankRepository.load(
      l2: course.l2,
      taken: await assessments.placementsTaken(course.id),
    );
    if (bank == null || bank.words.isEmpty) {
      return const PlacementState.unavailable();
    }
    _userId = userId;
    _course = course;
    _bank = bank;
    _seed = seed;
    _random = SeededRandom(seed);
    _words = _random.shuffled(bank.words);
    _parts = [
      PlacementPart.words,
      if (bank.grammar.isNotEmpty) PlacementPart.grammar,
      if (bank.dictation.isNotEmpty) PlacementPart.dictation,
    ];
    _known = [];
    _staircase = null;
    _choices = [];
    _written = [];
    _finished = {};
    _left = {};
    _durations = {};
    return PlacementState.overview(parts: _parts);
  }

  /// From the overview to the first part.
  void begin() {
    if (state.value is PlacementOverview) _next();
  }

  /// Starts the part that was introduced.
  void startPart() {
    final current = state.value;
    if (current is! PlacementPartIntro) return;
    _watch
      ..reset()
      ..start();
    switch (current.part) {
      case PlacementPart.words:
        _showWord();
      case PlacementPart.grammar:
        _staircase = Staircase.start(
          bank: _bank.grammar,
          seed: _random.nextInt(1 << 30),
        );
        _showQuestion();
      case PlacementPart.dictation:
        _showSentence(1);
    }
  }

  /// Whether the learner knows the word on screen.
  void answerWord({required bool known}) {
    if (state.value is! PlacementWord) return;
    _known.add(known);
    if (_known.length < _words.length) {
      _showWord();
    } else {
      _endPart(PlacementPart.words);
    }
  }

  /// The choice for the gap on screen; null says "not sure".
  void choose(String? option) {
    final staircase = _staircase;
    if (state.value is! PlacementQuestion || staircase == null) return;
    _choices.add(option);
    final next = staircase.answer(correct: option == staircase.current!.answer);
    _staircase = next;
    if (next.isFinished) {
      _endPart(PlacementPart.grammar);
    } else {
      _showQuestion();
    }
  }

  /// Plays the sentence on screen, fetching its clip first if needed.
  Future<void> listen() async {
    final current = state.value;
    if (current is! PlacementListening ||
        current.playing ||
        current.playsLeft == 0) {
      return;
    }
    state = AsyncData(current.copyWith(playing: true, failure: null));
    final sentence = _bank.dictation[current.number - 1];
    final file = await ref.read(packAudioProvider).file(sentence.clip);
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
    // The learner may have gone on while the clip played.
    if (state.value case PlacementListening(:final number)
        when number == current.number) {
      state = AsyncData(
        played
            ? current.copyWith(heard: true, playsLeft: current.playsLeft - 1)
            : current.copyWith(failure: failure),
      );
    }
  }

  /// What the learner wrote for the sentence on screen.
  void write(String typed) {
    final current = state.value;
    if (current is! PlacementListening || !current.heard) return;
    unawaited(ref.read(clipPlayerProvider).stop());
    final sentence = _bank.dictation[current.number - 1];
    _written.add((
      typed: typed,
      plays: plays - current.playsLeft,
      score: DictationScore.of(
        expected: sentence.text,
        typed: typed,
        language: _bank.language,
      ),
    ));
    if (current.number < _bank.dictation.length) {
      _showSentence(current.number + 1);
    } else {
      _endPart(PlacementPart.dictation);
    }
  }

  /// Leaves the dictation out, for a learner who cannot listen now.
  void skipDictation() {
    final skippable = switch (state.value) {
      PlacementPartIntro(part: PlacementPart.dictation) => true,
      PlacementListening() => true,
      _ => false,
    };
    if (!skippable) return;
    unawaited(ref.read(clipPlayerProvider).stop());
    _written = [];
    _left.add(PlacementPart.dictation);
    _next();
  }

  /// Ends the test here. The parts that were finished are saved; a part
  /// left half-way is not.
  Future<void> leave() async {
    switch (state.value) {
      case null ||
          PlacementUnavailable() ||
          PlacementSaving() ||
          PlacementDone():
        return;
      case _:
        unawaited(ref.read(clipPlayerProvider).stop());
        await _finish();
    }
  }

  void _showWord() => state = AsyncData(
    PlacementState.word(
      number: _known.length + 1,
      total: _words.length,
      word: _words[_known.length].word,
    ),
  );

  void _showQuestion() {
    final staircase = _staircase!;
    final question = staircase.current!;
    state = AsyncData(
      PlacementState.question(
        number: staircase.steps.length + 1,
        stem: question.stem,
        options: _random.shuffled([question.answer, ...question.distractors]),
      ),
    );
  }

  void _showSentence(int number) => state = AsyncData(
    PlacementState.listening(
      number: number,
      total: _bank.dictation.length,
      playsLeft: plays,
    ),
  );

  void _endPart(PlacementPart part) {
    _finished.add(part);
    _durations[part] = _watch.elapsedMilliseconds;
    _next();
  }

  /// The introduction of the next part, or the end of the test.
  void _next() {
    for (final part in _parts) {
      if (_finished.contains(part) || _left.contains(part)) continue;
      state = AsyncData(PlacementState.partIntro(part: part));
      return;
    }
    unawaited(_finish());
  }

  Future<void> _finish() async {
    if (_finished.isEmpty) {
      state = const AsyncData(PlacementState.done());
      return;
    }
    state = const AsyncData(PlacementState.saving());
    // Read before the first wait: the page may close while this saves.
    final assessments = ref.read(assessmentRepositoryProvider);
    final profiles = ref.read(profileRepositoryProvider);
    const source = PlacementOutcome.source;
    final staircase = _staircase;
    final xlex = XlexResult.of([
      for (final (index, known) in _known.indexed)
        XlexAnswer(known: known, band: _words[index].band),
    ]);
    final vocabulary = _bank.vocabLevels.estimate(xlex.score, source: source);
    final grammar = _finished.contains(PlacementPart.grammar)
        ? staircase!.estimate(source: source)
        : null;
    final listening = _finished.contains(PlacementPart.dictation)
        ? DictationScore.estimate([
            for (final (index, written) in _written.indexed)
              (_bank.dictation[index].level, written.score),
          ], source: source)
        : null;
    final outcome = PlacementOutcome.of(
      fallback: _course.level,
      vocabulary: vocabulary,
      grammar: grammar,
      listening: listening,
    );
    await assessments.savePlacement(
      userId: _userId,
      courseId: _course.id,
      outcome: outcome,
      vocabulary: xlex.score,
      results: {
        'version': _bank.version,
        'seed': _seed,
        'xlex': {
          ...xlex.toJson(),
          'answers': [
            for (final (index, known) in _known.indexed)
              {'key': _words[index].key, 'known': known},
          ],
        },
        if (grammar != null)
          'grammar': {
            'steps': [
              for (final (index, step) in staircase!.steps.indexed)
                {
                  'key': step.item.key,
                  'level': step.level.code,
                  'choice': _choices[index],
                  'correct': step.correct,
                },
            ],
          },
        if (listening != null)
          'dictation': {
            'sentences': [
              for (final (index, written) in _written.indexed)
                {
                  'key': _bank.dictation[index].key,
                  'level': _bank.dictation[index].level.code,
                  'typed': written.typed,
                  'plays': written.plays,
                  'words': written.score.words,
                  'errors': written.score.errors,
                  'slips': written.score.slips,
                },
            ],
          },
        'duration_ms': {
          for (final MapEntry(key: part, value: ms) in _durations.entries)
            part.name: ms,
        },
      },
    );
    // The course goes to the server right away; offline it waits in the
    // outbox like every other write.
    await profiles.push(_userId);
    if (!ref.mounted) return;
    state = AsyncData(
      PlacementState.done(
        report: PlacementReport(
          start: outcome.start,
          vocabulary: xlex.score,
          guesswork: xlex.isGuesswork,
          vocabularyLevel: vocabulary,
          grammarLevel: grammar,
          listeningLevel: listening,
        ),
      ),
    );
  }
}
