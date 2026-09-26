import 'package:json_annotation/json_annotation.dart';

/// Learning state of a card's memory, as scheduled by FSRS.
///
/// [code] is the value stored in `cards.state` and in
/// `attempts.card_state_after` (docs/13-data-model.md §2.3).
@JsonEnum(valueField: 'code')
enum MemoryState {
  /// New or still inside the learning steps.
  learning(1),

  /// Graduated; scheduled in days.
  review(2),

  /// Forgotten during review; inside the relearning steps.
  relearning(3);

  new(this.code);

  /// Stable integer code shared with the database and FSRS.
  final int code;
}
