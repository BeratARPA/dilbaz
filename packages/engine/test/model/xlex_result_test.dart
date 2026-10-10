import 'dart:convert';

import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

/// A full test: 20 real words per band and 20 made-up ones, with [yes]
/// accepted per band and [falseAlarms] made-up words accepted.
List<XlexAnswer> answers(List<int> yes, {required int falseAlarms}) => [
  for (final (index, accepted) in yes.indexed)
    for (var i = 0; i < 20; i++)
      XlexAnswer(band: index + 1, known: i < accepted),
  for (var i = 0; i < 20; i++) XlexAnswer(known: i < falseAlarms),
];

void main() {
  group('XlexResult (docs/06-assessment.md §2)', () {
    test('scores +50 per real word and −250 per made-up word', () {
      final result = XlexResult.of(answers([20, 15, 10, 5, 0], falseAlarms: 2));
      expect(result.score, 50 * 50 - 250 * 2);
      expect(result.bandRates, {1: 1.0, 2: 0.75, 3: 0.5, 4: 0.25, 5: 0.0});
      expect(result.falseAlarmRate, 0.1);
    });

    test('stays between 0 and 5000', () {
      final all = XlexResult.of(answers([20, 20, 20, 20, 20], falseAlarms: 0));
      expect(all.score, 5000);
      final yesToAll = XlexResult.of(
        answers([20, 20, 20, 20, 20], falseAlarms: 20),
      );
      expect(yesToAll.score, 0);
      final guesser = XlexResult.of(answers([2, 1, 0, 0, 0], falseAlarms: 10));
      expect(guesser.score, 0);
      expect(XlexResult.of(const []).score, 0);
    });

    test('is guesswork above 25% false alarms', () {
      final careful = XlexResult.of(answers([20, 10, 5, 0, 0], falseAlarms: 5));
      expect(careful.falseAlarmRate, XlexResult.maxFalseAlarmRate);
      expect(careful.isGuesswork, isFalse);
      final guesser = XlexResult.of(answers([20, 10, 5, 0, 0], falseAlarms: 6));
      expect(guesser.isGuesswork, isTrue);
    });

    test('band probabilities are the rates less the false alarms', () {
      final result = XlexResult.of(answers([20, 15, 10, 5, 0], falseAlarms: 2));
      expect(result.probability(1), closeTo(0.9, 1e-9));
      expect(result.probability(2), closeTo(0.65, 1e-9));
      expect(result.probability(3), closeTo(0.4, 1e-9));
      expect(result.probability(4), closeTo(0.15, 1e-9));
      // Never below zero; bands past the test take the last one's.
      expect(result.probability(5), 0);
      expect(result.probability(9), 0);
      final strong = XlexResult.of(
        answers([20, 20, 20, 20, 16], falseAlarms: 0),
      );
      expect(strong.probability(8), 0.8);
      // Together the bands give the score back.
      final total = [1, 2, 3, 4, 5].fold<double>(
        0,
        (sum, band) => sum + strong.probability(band) * XlexResult.bandSize,
      );
      expect(total.round(), strong.score);
    });

    test('a test without made-up words has no false alarms', () {
      final result = XlexResult.of([
        const XlexAnswer(band: 1, known: true),
        const XlexAnswer(band: 1, known: false),
      ]);
      expect(result.falseAlarmRate, 0);
      expect(result.score, 500);
      expect(
        const XlexResult(
          score: 0,
          bandRates: {},
          falseAlarmRate: 0,
        ).probability(1),
        0,
      );
    });

    test('bands are thousands of the frequency list', () {
      expect(XlexResult.bandOf(1), 1);
      expect(XlexResult.bandOf(1000), 1);
      expect(XlexResult.bandOf(1001), 2);
      expect(XlexResult.bandOf(5000), 5);
      expect(XlexResult.bandOf(5001), 6);
    });

    test('round-trips through assessments.results JSON', () {
      final result = XlexResult.of(answers([20, 15, 10, 5, 0], falseAlarms: 2));
      final json = jsonDecode(jsonEncode(result.toJson()));
      expect(XlexResult.fromJson(json as Map<String, Object?>), result);
      expect(result.toJson().keys, ['score', 'band_rates', 'false_alarm_rate']);
    });
  });
}
