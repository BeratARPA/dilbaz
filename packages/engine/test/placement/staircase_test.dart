import 'dart:math';

import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  const a1 = CefrLevel.a1;
  const a2 = CefrLevel.a2;
  const b1 = CefrLevel.b1;
  const b2 = CefrLevel.b2;

  /// A bank with [perLevel] items at each of [levels]; an item is named by
  /// its level code and number.
  Map<CefrLevel, List<String>> bank({
    List<CefrLevel> levels = const [a1, a2, b1, b2],
    int perLevel = 12,
  }) => {
    for (final level in levels)
      level: [for (var i = 0; i < perLevel; i++) '${level.code}.$i'],
  };

  /// Runs a test to its end; [knows] answers each item from its level.
  Staircase<String> run(
    bool Function(CefrLevel level, int step) knows, {
    Map<CefrLevel, List<String>>? items,
    int seed = 7,
    StaircaseConfig config = const StaircaseConfig(),
  }) {
    var test = Staircase.start(
      bank: items ?? bank(),
      seed: seed,
      config: config,
    );
    while (!test.isFinished) {
      test = test.answer(correct: knows(test.currentLevel!, test.steps.length));
    }
    return test;
  }

  group('Staircase (docs/06-assessment.md §2, part 2)', () {
    test('starts with an A2 item', () {
      final test = Staircase.start(bank: bank(), seed: 1);
      expect(test.currentLevel, a2);
      expect(test.current, startsWith('A2.'));
      expect(test.steps, isEmpty);
      expect(test.isFinished, isFalse);
    });

    test('a bank without the start level begins just below it', () {
      expect(
        Staircase.start(bank: bank(levels: [a1, b1, b2]), seed: 1).currentLevel,
        a1,
      );
      expect(
        Staircase.start(bank: bank(levels: [b1, b2]), seed: 1).currentLevel,
        b1,
      );
    });

    test('a right answer goes one level up, any other one down', () {
      var test = Staircase.start(bank: bank(), seed: 1);
      test = test.answer(correct: true);
      expect(test.currentLevel, b1);
      test = test.answer(correct: true);
      expect(test.currentLevel, b2);
      test = test.answer(correct: true);
      expect(test.currentLevel, b2, reason: 'the top of the bank');
      test = test.answer(correct: false);
      expect(test.currentLevel, b1);
      test = test.answer(correct: false);
      test = test.answer(correct: false);
      expect(test.currentLevel, a1);
      test = test.answer(correct: false);
      expect(test.currentLevel, a1, reason: 'the bottom of the bank');
      expect(
        [for (final step in test.steps) step.level],
        [a2, b1, b2, b2, b1, a2, a1],
      );
    });

    test('is immutable: an answer leaves the state it came from alone', () {
      final before = Staircase.start(bank: bank(), seed: 1);
      final after = before.answer(correct: true);
      expect(before.steps, isEmpty);
      expect(after.steps, hasLength(1));
      expect(after.steps.single.item, before.current);
    });

    test('never asks an item twice', () {
      final test = run((level, step) => step.isEven);
      final asked = [for (final step in test.steps) step.item];
      expect(asked.toSet(), hasLength(asked.length));
    });

    test('draws the items of a level in the order of the seed', () {
      List<String> items(int seed) => [
        for (final step in run((_, _) => false, seed: seed).steps) step.item,
      ];
      expect(items(3), items(3));
      expect(items(3), isNot(items(4)));
    });

    test('ends after 12 items once it has settled', () {
      // Right up to A2, never above: the test circles A2 and B1.
      final test = run((level, _) => level.isAtMost(a2));
      expect(test.steps, hasLength(12));
      expect(test.current, isNull);
      expect(test.currentLevel, isNotNull);
    });

    test('goes on to 15 items while it has not settled', () {
      // Two right, two wrong, again and again: the test swings over three
      // levels and never stays within two.
      final test = run((_, step) => step % 4 < 2);
      expect(test.steps, hasLength(15));
    });

    test('ends when the bank is used up', () {
      final test = run(
        (_, _) => true,
        items: bank(levels: [a2, b1], perLevel: 2),
      );
      expect(test.steps, hasLength(4));
      expect(test.isFinished, isTrue);
      expect(test.currentLevel, isNull);
      expect(() => test.answer(correct: true), throwsStateError);
    });

    test('a level without items left gives way to the nearest one', () {
      // Always right: the test stays at the top until B2 runs out.
      final test = run(
        (_, _) => true,
        items: {
          ...bank(levels: [a1, a2, b1]),
          b2: ['B2.0', 'B2.1'],
        },
        config: const StaircaseConfig(minItems: 8, maxItems: 8),
      );
      expect(
        [for (final step in test.steps) step.level],
        [a2, b1, b2, b2, b1, b1, b1, b1],
      );
    });

    test('of two equally near levels it takes the lower', () {
      var test = Staircase.start(
        bank: {
          a1: ['A1.0', 'A1.1'],
          a2: ['A2.0'],
          b1: ['B1.0', 'B1.1'],
        },
        seed: 1,
      );
      test = test.answer(correct: false); // A2 used up, wants A1.
      test = test.answer(correct: true); // wants A2, which is empty.
      expect(test.currentLevel, a1);
    });

    test('an empty bank is refused', () {
      expect(
        () => Staircase.start(bank: <CefrLevel, List<String>>{}, seed: 1),
        throwsArgumentError,
      );
      expect(
        () => Staircase.start(bank: {a2: <String>[]}, seed: 1),
        throwsArgumentError,
      );
    });
  });

  group('Staircase verdicts', () {
    Staircase<String> answered(List<bool> answers) {
      // One level only, so every answer counts for it.
      var test = Staircase.start(bank: bank(levels: [a2]), seed: 1);
      for (final correct in answers) {
        test = test.answer(correct: correct);
      }
      return test;
    }

    test('one item decides nothing', () {
      expect(answered([true]).shown, {a2: null});
      expect(answered([false]).shown, {a2: null});
    });

    test('two thirds right reach a level, one third or less miss it', () {
      expect(answered([true, true]).shown, {a2: true});
      expect(answered([true, false]).shown, {a2: null});
      expect(answered([false, false]).shown, {a2: false});
      expect(answered([true, true, false]).shown, {a2: true});
      expect(answered([true, false, false]).shown, {a2: false});
      expect(answered([true, true, false, false]).shown, {a2: null});
      expect(answered([true, true, true, false]).shown, {a2: true});
      expect(answered([true, false, false, false]).shown, {a2: false});
    });

    test('tallies the levels asked', () {
      final test = run((level, _) => level.isAtMost(a2));
      expect(test.tally.keys, [a2, b1]);
      expect(test.tally[a2], (asked: 6, correct: 6));
      expect(test.tally[b1], (asked: 6, correct: 0));
      expect(test.shown, {a2: true, b1: false});
    });
  });

  group('Staircase estimates', () {
    test('a learner who holds A2 and no more is placed at A2', () {
      final test = run((level, _) => level.isAtMost(a2));
      expect(
        test.estimate(source: 'placement'),
        LevelEstimate.at(a2, source: 'placement'),
      );
    });

    test('a learner above the bank is placed at its top, open upwards', () {
      final test = run((_, _) => true);
      expect(test.estimate(), LevelEstimate.between(b2, CefrLevel.c2));
    });

    test('a learner under the bank is placed below its lowest level', () {
      final test = run((_, _) => false);
      expect(test.estimate(), LevelEstimate.at(CefrLevel.a0));
    });

    test('a learner at B1 is placed at B1', () {
      final test = run((level, _) => level.isAtMost(b1));
      expect(test.estimate(), LevelEstimate.at(b1));
    });

    test('whatever the answers, the test ends and gives a range', () {
      final random = Random(11);
      for (var trial = 0; trial < 300; trial++) {
        // Chance of a right answer falls with the level, around a threshold
        // drawn for the trial.
        final threshold = random.nextDouble() * 5;
        final test = run(
          (level, _) =>
              random.nextDouble() <
              (0.9 - 0.3 * (level.scale - threshold)).clamp(0.2, 0.95),
          seed: trial,
        );
        expect(test.steps.length, inInclusiveRange(12, 15));
        final estimate = test.estimate();
        expect(estimate.low, lessThanOrEqualTo(estimate.high));
        expect({
          for (final step in test.steps) step.item,
        }, hasLength(test.steps.length));
        // Neighbouring steps are at most one level apart.
        for (var i = 1; i < test.steps.length; i++) {
          expect(
            (test.steps[i].level.index - test.steps[i - 1].level.index).abs(),
            lessThanOrEqualTo(1),
          );
        }
      }
    });
  });
}
