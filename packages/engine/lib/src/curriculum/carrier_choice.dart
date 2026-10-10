import 'package:dilbaz_engine/src/curriculum/content_item.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'carrier_choice.freezed.dart';

/// A carrier for a new item and how well the learner knows its other
/// words (docs/02-curriculum.md §4.4).
@freezed
abstract class CarrierChoice with _$CarrierChoice {
  /// Creates a choice.
  const factory({
    /// The carrier: a sentence, or the chunk itself.
    required ContentItem carrier,

    /// How many of its other lemmas the learner is expected not to know.
    required double unknown,

    /// Whether every other word counts as known (i+1).
    required bool fits,
  }) = _CarrierChoice;
}
