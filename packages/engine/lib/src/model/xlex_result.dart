import 'package:dilbaz_engine/src/model/xlex_answer.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'xlex_result.freezed.dart';
part 'xlex_result.g.dart';

/// Result of an X_Lex yes/no test (Meara & Milton; docs/06-assessment.md
/// §2): how many of the most frequent lemmas the learner recognizes, with
/// "yes" to made-up words counted against it.
@freezed
abstract class XlexResult with _$XlexResult {
  /// Creates a result; [XlexResult.of] computes one from the answers.
  const factory({
    /// Recognition vocabulary size, from 0 to bands × [bandSize].
    required int score,

    /// Band → share of its real words accepted.
    required Map<int, double> bandRates,

    /// Share of the made-up words accepted.
    required double falseAlarmRate,
  }) = _XlexResult;

  /// Scores a finished test: each band's acceptance rate less the false
  /// alarm rate, times [bandSize]. With 20 real words per band and 20
  /// made-up ones that is +50 for a real word and −250 for a made-up one.
  factory of(Iterable<XlexAnswer> answers) {
    final asked = <int, int>{};
    final accepted = <int, int>{};
    var fake = 0;
    var falseAlarms = 0;
    for (final XlexAnswer(:band, :known) in answers) {
      if (band == null) {
        fake++;
        if (known) falseAlarms++;
      } else {
        asked[band] = (asked[band] ?? 0) + 1;
        if (known) accepted[band] = (accepted[band] ?? 0) + 1;
      }
    }
    final falseAlarmRate = fake == 0 ? 0.0 : falseAlarms / fake;
    final bandRates = {
      for (final band in asked.keys.toList()..sort())
        band: (accepted[band] ?? 0) / asked[band]!,
    };
    final ceiling = bandRates.length * bandSize;
    final raw = bandRates.values.fold<double>(
      0,
      (sum, rate) => sum + (rate - falseAlarmRate) * bandSize,
    );
    return XlexResult(
      score: raw.round().clamp(0, ceiling),
      bandRates: bandRates,
      falseAlarmRate: falseAlarmRate,
    );
  }

  /// Reads a result from `assessments.results`.
  factory fromJson(Map<String, Object?> json) => _$XlexResultFromJson(json);

  const new _();

  /// Lemmas per frequency band.
  static const bandSize = 1000;

  /// Above this false alarm rate the result is guesswork.
  static const maxFalseAlarmRate = 0.25;

  /// The band of a lemma with frequency [rank] (1 is the most frequent).
  static int bandOf(int rank) => (rank - 1) ~/ bandSize + 1;

  /// Whether the learner said yes to so many made-up words that the result
  /// is guesswork; its confidence is then low.
  bool get isGuesswork => falseAlarmRate > maxFalseAlarmRate;

  /// Probability that the learner knows a lemma of [band]: the band's
  /// acceptance rate less the false alarm rate. Bands past the last tested
  /// one take its probability.
  double probability(int band) {
    if (bandRates.isEmpty) return 0;
    final last = bandRates.keys.reduce((a, b) => a > b ? a : b);
    final rate = bandRates[band > last ? last : band] ?? 0;
    return (rate - falseAlarmRate).clamp(0, 1).toDouble();
  }
}
