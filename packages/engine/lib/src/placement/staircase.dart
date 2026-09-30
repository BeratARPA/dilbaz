import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/model/level_estimate.dart';
import 'package:dilbaz_engine/src/placement/level_ladder.dart';
import 'package:dilbaz_engine/src/placement/staircase_config.dart';
import 'package:dilbaz_engine/src/planner/seeded_random.dart';

/// One answered item of a [Staircase].
typedef StaircaseStep<T> = ({T item, CefrLevel level, bool correct});

/// An adaptive test over a bank of items with levels
/// (docs/06-assessment.md §2, part 2).
///
/// A right answer takes the next item from one level up, any other answer
/// from one level down, so the test circles the level where the learner
/// starts to miss. Immutable: [answer] returns the next state.
final class Staircase<T> {
  /// A test over [bank] (level → its items). The [seed] fixes the order in
  /// which the items of a level are drawn.
  factory start({
    required Map<CefrLevel, List<T>> bank,
    required int seed,
    StaircaseConfig config = const StaircaseConfig(),
  }) {
    final random = SeededRandom(seed);
    final levels = [
      for (final level in CefrLevel.values)
        if (bank[level]?.isNotEmpty ?? false) level,
    ];
    if (levels.isEmpty) throw ArgumentError.value(bank, 'bank', 'empty');
    return Staircase._(
      bank: {for (final level in levels) level: random.shuffled(bank[level]!)},
      levels: levels,
      config: config,
      steps: const [],
      level: levels.lastWhere(
        (level) => level.isAtMost(config.start),
        orElse: () => levels.first,
      ),
    );
  }

  const new _({
    required this._bank,
    required this.levels,
    required this.config,
    required this.steps,
    required this._level,
  });

  final Map<CefrLevel, List<T>> _bank;

  /// The level the next item is wanted from.
  final CefrLevel _level;

  /// Levels the bank has items of, ascending.
  final List<CefrLevel> levels;

  /// Settings of the test.
  final StaircaseConfig config;

  /// The answered items, in order.
  final List<StaircaseStep<T>> steps;

  /// The item to ask now; null once the test is over.
  T? get current {
    if (isFinished) return null;
    final level = currentLevel!;
    return _bank[level]![_asked(level)];
  }

  /// Level of [current]: the wanted level, or the nearest one that still
  /// has items, the lower of two equally near. Null when no item is left.
  CefrLevel? get currentLevel {
    final wanted = levels.indexOf(_level);
    CefrLevel? nearest;
    var distance = levels.length;
    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      if (_asked(level) >= _bank[level]!.length) continue;
      if ((i - wanted).abs() < distance) {
        nearest = level;
        distance = (i - wanted).abs();
      }
    }
    return nearest;
  }

  /// Whether the test is over: it ran its length, settled, or ran out of
  /// items.
  bool get isFinished =>
      steps.length >= config.maxItems ||
      currentLevel == null ||
      (steps.length >= config.minItems && _settled);

  /// Records the answer to [current].
  Staircase<T> answer({required bool correct}) {
    final item = current;
    if (item == null) throw StateError('finished');
    final level = currentLevel!;
    final index = levels.indexOf(level) + (correct ? 1 : -1);
    return Staircase._(
      bank: _bank,
      levels: levels,
      config: config,
      steps: [...steps, (item: item, level: level, correct: correct)],
      level: levels[index.clamp(0, levels.length - 1)],
    );
  }

  /// Asked and right answers of each level asked.
  Map<CefrLevel, ({int asked, int correct})> get tally => {
    for (final level in levels)
      if (_asked(level) > 0)
        level: (
          asked: _asked(level),
          correct: steps.where((s) => s.level == level && s.correct).length,
        ),
  };

  /// What the answers show of each level asked: reached, not reached, or
  /// neither (null).
  Map<CefrLevel, bool?> get shown => {
    for (final MapEntry(key: level, value: (:asked, :correct)) in tally.entries)
      level: asked < config.minPerLevel
          ? null
          : correct / asked >= config.reachedShare
          ? true
          : correct / asked <= config.missedShare
          ? false
          : null,
  };

  /// The level range the answers point to.
  LevelEstimate estimate({String? source}) =>
      LevelLadder.estimate(shown, tested: levels, source: source);

  int _asked(CefrLevel level) => steps.where((s) => s.level == level).length;

  /// The last [StaircaseConfig.window] items stayed within two neighbouring
  /// levels.
  bool get _settled {
    if (steps.length < config.window) return false;
    final recent = [
      for (final step in steps.skip(steps.length - config.window))
        levels.indexOf(step.level),
    ];
    final lowest = recent.reduce((a, b) => a < b ? a : b);
    final highest = recent.reduce((a, b) => a > b ? a : b);
    return highest - lowest <= 1;
  }
}
