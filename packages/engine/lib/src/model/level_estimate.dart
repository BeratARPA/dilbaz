import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/model/confidence.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'level_estimate.freezed.dart';
part 'level_estimate.g.dart';

/// A level as a range with its confidence, never a single number that
/// claims more than the evidence holds (I-04, docs/04-learner-model.md §7).
///
/// The ends are on the numeric scale: A0 = 0 … C2 = 6.
@freezed
abstract class LevelEstimate with _$LevelEstimate {
  /// Creates an estimate from [low] to [high].
  const factory({
    /// The level the evidence shows as reached.
    required double low,

    /// The highest level the evidence does not rule out.
    required double high,

    /// How much evidence stands behind the range.
    @Default(Confidence.low) Confidence confidence,

    /// What the estimate rests on, such as `self` or `placement`.
    String? source,
  }) = _LevelEstimate;

  /// An estimate that names one level.
  factory at(
    CefrLevel level, {
    Confidence confidence = Confidence.low,
    String? source,
  }) => LevelEstimate(
    low: level.scale.toDouble(),
    high: level.scale.toDouble(),
    confidence: confidence,
    source: source,
  );

  /// An estimate from [low] to [high].
  factory between(
    CefrLevel low,
    CefrLevel high, {
    Confidence confidence = Confidence.low,
    String? source,
  }) => LevelEstimate(
    low: low.scale.toDouble(),
    high: high.scale.toDouble(),
    confidence: confidence,
    source: source,
  );

  /// Reads an entry of `courses.level_estimates`.
  factory fromJson(Map<String, Object?> json) => _$LevelEstimateFromJson(json);

  const new _();

  /// The level reached: the whole level at the lower end.
  CefrLevel get reached => _level(low);

  /// The highest level not ruled out: the whole level at the upper end.
  CefrLevel get ceiling => _level(high);

  /// Whether the range names a single level.
  bool get isPoint => reached == ceiling;

  static CefrLevel _level(double scale) =>
      CefrLevel.values[scale.floor().clamp(0, CefrLevel.values.length - 1)];
}
