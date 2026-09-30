import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  // The shape of `placement.vocab_levels` in a pack manifest, with a gap
  // between the second and the third level and the entries out of order.
  final levels = VocabLevels.fromJson(const [
    {'level': 'B1', 'from': 2750, 'to': 3250},
    {'level': 'A0', 'from': 0, 'to': 300},
    {'level': 'A2', 'from': 1500, 'to': 2500},
    {'level': 'A1', 'from': 300, 'to': 1500},
  ]);

  group('VocabLevels (docs/02-curriculum.md §2)', () {
    test('reads the ranges of the pack, lowest first', () {
      expect(
        [for (final range in levels.ranges) range.level],
        [CefrLevel.a0, CefrLevel.a1, CefrLevel.a2, CefrLevel.b1],
      );
      expect(levels.ranges[2], (level: CefrLevel.a2, from: 1500, to: 2500));
    });

    test('a score inside a range names its level', () {
      expect(levels.estimate(0), LevelEstimate.at(CefrLevel.a0));
      expect(levels.estimate(299), LevelEstimate.at(CefrLevel.a0));
      expect(levels.estimate(300), LevelEstimate.at(CefrLevel.a1));
      expect(levels.estimate(1850), LevelEstimate.at(CefrLevel.a2));
      expect(levels.estimate(3249), LevelEstimate.at(CefrLevel.b1));
    });

    test('a score between two ranges spans both levels', () {
      expect(
        levels.estimate(2600),
        LevelEstimate.between(CefrLevel.a2, CefrLevel.b1),
      );
      expect(
        levels.estimate(2500),
        LevelEstimate.between(CefrLevel.a2, CefrLevel.b1),
      );
    });

    test('a score past the last range stays at the last level', () {
      expect(levels.estimate(4000), LevelEstimate.at(CefrLevel.b1));
    });

    test('carries the source', () {
      expect(levels.estimate(1850, source: 'placement').source, 'placement');
    });
  });
}
