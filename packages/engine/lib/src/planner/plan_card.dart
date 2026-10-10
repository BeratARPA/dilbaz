import 'package:dilbaz_engine/src/fsrs/card_memory.dart';
import 'package:dilbaz_engine/src/fsrs/card_mode.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'plan_card.freezed.dart';

/// A card as the planner sees it.
@freezed
abstract class PlanCard with _$PlanCard {
  /// Creates a card.
  const factory({
    /// Id of the card (`cards.id`).
    required String id,

    /// Key of its item.
    required String itemKey,

    /// How it is practised.
    required CardMode mode,

    /// Its FSRS memory.
    required CardMemory memory,

    /// Tied to the weekly error focus.
    @Default(false) bool focus,
  }) = _PlanCard;
}
