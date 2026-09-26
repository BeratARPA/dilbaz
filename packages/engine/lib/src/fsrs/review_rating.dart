import 'package:json_annotation/json_annotation.dart';

/// FSRS rating of a single review.
///
/// Ratings are computed from the learner's performance, never from
/// self-assessment (docs/03-activities.md §0.3). [code] is the value stored
/// in `attempts.rating`.
@JsonEnum(valueField: 'code')
enum ReviewRating {
  /// Not recalled.
  again(1),

  /// Recalled with difficulty.
  hard(2),

  /// Recalled.
  good(3),

  /// Recalled easily.
  easy(4);

  new(this.code);

  /// Stable integer code shared with the database and FSRS.
  final int code;
}
