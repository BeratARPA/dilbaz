import 'dart:convert';

import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  const a1 = CefrLevel.a1;
  const a2 = CefrLevel.a2;
  const b1 = CefrLevel.b1;

  group('PlacementOutcome (docs/06-assessment.md §2)', () {
    test('the curriculum starts at the weaker of vocabulary and grammar', () {
      final outcome = PlacementOutcome.of(
        fallback: b1,
        vocabulary: LevelEstimate.at(a2),
        grammar: LevelEstimate.between(a1, a2),
      );
      expect(outcome.start, a1);
      expect(outcome.measured, isTrue);
      expect(
        PlacementOutcome.of(
          fallback: b1,
          vocabulary: LevelEstimate.at(a1),
          grammar: LevelEstimate.at(b1),
        ).start,
        a1,
      );
    });

    test('listening has its own estimate and does not move the start', () {
      final outcome = PlacementOutcome.of(
        fallback: b1,
        vocabulary: LevelEstimate.at(a2),
        grammar: LevelEstimate.at(a2),
        listening: LevelEstimate.at(CefrLevel.a0),
      );
      expect(outcome.start, a2);
      expect(outcome.skills[Skill.listening], LevelEstimate.at(CefrLevel.a0));
    });

    test('one part alone decides the start', () {
      expect(
        PlacementOutcome.of(
          fallback: b1,
          vocabulary: LevelEstimate.at(a2),
        ).start,
        a2,
      );
      expect(
        PlacementOutcome.of(fallback: b1, grammar: LevelEstimate.at(a1)).start,
        a1,
      );
    });

    test('without vocabulary and grammar the chosen level stays', () {
      final outcome = PlacementOutcome.of(
        fallback: a2,
        listening: LevelEstimate.at(a1),
      );
      expect(outcome.start, a2);
      expect(outcome.measured, isFalse);
      // The course keeps its self-reported level: nothing overwrites it.
      expect(outcome.toLevelEstimates().keys, ['listening']);
    });

    test('writes the tested skills and the start into the course', () {
      final outcome = PlacementOutcome.of(
        fallback: b1,
        vocabulary: LevelEstimate.at(a2, source: PlacementOutcome.source),
        grammar: LevelEstimate.between(a1, a2, source: PlacementOutcome.source),
      );
      expect(jsonDecode(jsonEncode(outcome.toLevelEstimates())), {
        'vocabulary': {
          'low': 2.0,
          'high': 2.0,
          'confidence': 'low',
          'source': 'placement',
        },
        'grammar': {
          'low': 1.0,
          'high': 2.0,
          'confidence': 'low',
          'source': 'placement',
        },
        'overall': {
          'low': 1.0,
          'high': 1.0,
          'confidence': 'low',
          'source': 'placement',
        },
      });
      expect(outcome.skills.keys, [Skill.vocabulary, Skill.grammar]);
    });
  });
}
