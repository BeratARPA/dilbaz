import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  const a0 = CefrLevel.a0;
  const a1 = CefrLevel.a1;
  const a2 = CefrLevel.a2;
  const b1 = CefrLevel.b1;
  const b2 = CefrLevel.b2;
  const tested = [a1, a2, b1, b2];

  LevelEstimate estimate(
    Map<CefrLevel, bool?> shown, {
    List<CefrLevel> levels = tested,
  }) => LevelLadder.estimate(shown, tested: levels);

  group('LevelLadder (docs/06-assessment.md §2)', () {
    test('reached up to a level, missed above it: that level', () {
      expect(estimate({a1: true, a2: true, b1: false}), LevelEstimate.at(a2));
    });

    test('an undecided level above widens the range', () {
      expect(estimate({a2: true, b1: null}), LevelEstimate.between(a2, b1));
      expect(
        estimate({a2: true, b1: null, b2: false}),
        LevelEstimate.between(a2, b1),
      );
    });

    test('the lowest level missed: the level under it', () {
      expect(estimate({a1: false}), LevelEstimate.at(a0));
      expect(estimate({a2: false, a1: false}), LevelEstimate.at(a0));
    });

    test('there is nothing under the bottom of the scale', () {
      expect(estimate({a0: false}, levels: [a0, a1]), LevelEstimate.at(a0));
    });

    test('nothing reached and the lowest undecided: up to that level', () {
      expect(estimate({a1: null, a2: false}), LevelEstimate.between(a0, a1));
    });

    test('the top reached: open to the end of the scale', () {
      expect(
        estimate({a2: true, b1: true, b2: true}),
        LevelEstimate.between(b2, CefrLevel.c2),
      );
    });

    test('levels that were never asked do not hold the estimate down', () {
      // The test started at A2 and went up: A1 was never asked.
      expect(estimate({a2: true, b1: false}), LevelEstimate.at(a2));
      // Levels above the last one asked were never in reach.
      expect(estimate({a1: true, a2: null}), LevelEstimate.between(a1, a2));
    });

    test('a level reached above a missed one does not count', () {
      // Levels build on each other; a lucky run higher up is noise.
      expect(estimate({a1: true, a2: false, b1: true}), LevelEstimate.at(a1));
    });

    test('carries the source', () {
      expect(
        LevelLadder.estimate(
          {a1: true, a2: false},
          tested: tested,
          source: 'placement',
        ).source,
        'placement',
      );
    });

    test('the lower end never passes the upper end', () {
      const verdicts = [true, false, null];
      for (var code = 0; code < 81; code++) {
        final shown = {
          for (final (i, level) in tested.indexed)
            level: verdicts[(code ~/ [1, 3, 9, 27][i]) % 3],
        };
        final result = estimate(shown);
        expect(result.low, lessThanOrEqualTo(result.high), reason: '$shown');
      }
    });
  });
}
