import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'staircase_config.freezed.dart';

/// Settings of an adaptive level test (docs/06-assessment.md §2, part 2).
@freezed
abstract class StaircaseConfig with _$StaircaseConfig {
  /// Creates settings; the defaults are the documented values.
  const factory({
    /// Level of the first item.
    @Default(CefrLevel.a2) CefrLevel start,

    /// Items asked before the test may end.
    @Default(12) int minItems,

    /// Items after which the test ends in any case.
    @Default(15) int maxItems,

    /// The test has settled when its last items, this many, stayed within
    /// two neighbouring levels.
    @Default(6) int window,

    /// Items a level needs before its answers decide anything.
    @Default(2) int minPerLevel,

    /// A level is reached from this share of right answers on.
    @Default(2 / 3) double reachedShare,

    /// A level is not reached up to this share of right answers.
    @Default(1 / 3) double missedShare,
  }) = _StaircaseConfig;
}
