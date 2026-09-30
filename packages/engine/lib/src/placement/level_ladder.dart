import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/model/level_estimate.dart';

/// Turns what a test showed level by level into a level range
/// (docs/06-assessment.md §2).
abstract final class LevelLadder {
  /// The estimate for a test that can ask the [tested] levels (ascending).
  ///
  /// [shown] holds the levels that were asked: true where the level was
  /// reached, false where it was not, null where the answers decide
  /// neither. Levels are taken to build on each other:
  ///
  /// - the lower end is the highest level reached below the first level
  ///   that was not; with nothing reached it is the level under the lowest
  ///   tested one;
  /// - the upper end is the highest level asked that was not ruled out;
  /// - when the highest tested level is reached, the test cannot tell how
  ///   far above it the learner is, and the range stays open to the top of
  ///   the scale.
  static LevelEstimate estimate(
    Map<CefrLevel, bool?> shown, {
    required List<CefrLevel> tested,
    String? source,
  }) {
    final bottom = tested.first;
    var low = bottom == CefrLevel.values.first
        ? bottom
        : CefrLevel.values[bottom.index - 1];
    CefrLevel? missed;
    for (final level in tested) {
      if (!shown.containsKey(level)) continue;
      final reached = shown[level];
      if (reached == false) {
        missed = level;
        break;
      }
      if (reached ?? false) low = level;
    }
    if (low == tested.last) {
      return LevelEstimate.between(low, CefrLevel.values.last, source: source);
    }
    var high = low;
    for (final level in tested) {
      if (level.index <= high.index || !shown.containsKey(level)) continue;
      if (missed != null && level.index >= missed.index) break;
      high = level;
    }
    return LevelEstimate.between(low, high, source: source);
  }
}
