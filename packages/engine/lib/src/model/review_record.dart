import 'package:dilbaz_engine/src/fsrs/review_rating.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'review_record.freezed.dart';

/// One rated review of a card, as the learner model reads it back from
/// `attempts` (docs/04-learner-model.md §1: every level is a projection of
/// that log).
@freezed
abstract class ReviewRecord with _$ReviewRecord {
  /// Creates a record.
  const factory({
    /// When the review was rated (UTC).
    required DateTime at,

    /// Its automatic rating.
    required ReviewRating rating,

    /// Whether the learner produced (or recognized) the target in it. False
    /// for a miss, and for a review that ended without the target or
    /// undecided (docs/03-activities.md §0.3).
    required bool evidence,

    /// Stability after it, in days (`card_state_after.stability`).
    required double stability,
  }) = _ReviewRecord;

  const new _();

  /// A recall on the first try, without hints.
  bool get unaided =>
      evidence && (rating == ReviewRating.good || rating == ReviewRating.easy);
}
