import 'package:dilbaz_engine/src/curriculum/item_kind.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'curriculum_config.freezed.dart';

/// Weights of the curriculum order (docs/02-curriculum.md §4.3). The
/// defaults are the documented values; experiments may override them.
@freezed
abstract class CurriculumConfig with _$CurriculumConfig {
  /// Creates curriculum settings.
  const factory({
    /// Kinds of items that are introduced as new items.
    @Default(<ItemKind>{ItemKind.wordSense, ItemKind.chunk})
    Set<ItemKind> introducible,

    /// Weight of an item the learner asked for themselves.
    @Default(3) double personalWeight,

    /// Weight of how well the item's level fits the learner's.
    @Default(2) double levelWeight,

    /// Weight of the item's frequency.
    @Default(1.5) double frequencyWeight,

    /// Weight of an item tied to the weekly error focus.
    @Default(1) double focusWeight,

    /// Weight of an item that supports a can-do not shown yet.
    @Default(0.5) double canDoWeight,

    /// Taken off an item that is easily confused with one introduced in
    /// the last three days.
    @Default(1) double similarityPenalty,

    /// Level fit two levels above the learner's.
    @Default(0.3) double twoAboveFit,

    /// Level fit below the learner's level: probably known already.
    @Default(0.5) double belowFit,

    /// Frequency score of an item without a frequency rank, such as a
    /// chunk.
    @Default(0.5) double unrankedFrequency,
  }) = _CurriculumConfig;
}
