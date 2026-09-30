import 'dart:convert';

import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  group('LevelEstimate (docs/04-learner-model.md §7)', () {
    test('names one level or a range on the numeric scale', () {
      final point = LevelEstimate.at(CefrLevel.a2);
      expect((point.low, point.high), (2.0, 2.0));
      expect(point.isPoint, isTrue);
      expect(point.reached, CefrLevel.a2);

      final range = LevelEstimate.between(CefrLevel.a2, CefrLevel.b1);
      expect((range.low, range.high), (2.0, 3.0));
      expect(range.isPoint, isFalse);
      expect(range.reached, CefrLevel.a2);
      expect(range.ceiling, CefrLevel.b1);
    });

    test('starts with low confidence', () {
      expect(LevelEstimate.at(CefrLevel.a1).confidence, Confidence.low);
      expect(
        LevelEstimate.at(CefrLevel.a1, confidence: Confidence.high).confidence,
        Confidence.high,
      );
    });

    test('a "+" sublevel has reached the level below it', () {
      const plus = LevelEstimate(low: 2.5, high: 3.5);
      expect(plus.reached, CefrLevel.a2);
      expect(plus.ceiling, CefrLevel.b1);
    });

    test('stays on the scale', () {
      const off = LevelEstimate(low: -1, high: 9);
      expect(off.reached, CefrLevel.a0);
      expect(off.ceiling, CefrLevel.c2);
    });

    test('round-trips through the course JSON', () {
      final estimate = LevelEstimate.between(
        CefrLevel.a1,
        CefrLevel.a2,
        confidence: Confidence.medium,
        source: 'placement',
      );
      final json = jsonDecode(jsonEncode(estimate.toJson()));
      expect(json, {
        'low': 1.0,
        'high': 2.0,
        'confidence': 'medium',
        'source': 'placement',
      });
      expect(LevelEstimate.fromJson(json as Map<String, Object?>), estimate);
    });

    test('reads the self-reported level of the welcome flow', () {
      final estimate = LevelEstimate.fromJson(const {
        'low': 2,
        'high': 2,
        'confidence': 'low',
        'source': 'self',
      });
      expect(estimate, LevelEstimate.at(CefrLevel.a2, source: 'self'));
    });

    test('every skill and confidence has a distinct code', () {
      expect({for (final skill in Skill.values) skill.code}, hasLength(6));
      expect({for (final c in Confidence.values) c.code}, hasLength(3));
    });
  });
}
