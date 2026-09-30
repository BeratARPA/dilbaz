import 'package:dilbaz_engine/src/fsrs/card_memory.dart';
import 'package:dilbaz_engine/src/fsrs/card_mode.dart';
import 'package:dilbaz_engine/src/fsrs/memory_state.dart';
import 'package:dilbaz_engine/src/model/item_level.dart';
import 'package:dilbaz_engine/src/model/review_record.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'card_record.freezed.dart';

/// A card with its rated reviews: what the learner model knows of one
/// learner × item × mode (docs/04-learner-model.md §2–3).
@freezed
abstract class CardRecord with _$CardRecord {
  /// Creates a record.
  const factory({
    /// How the card is practised.
    required CardMode mode,

    /// Its FSRS memory now.
    required CardMemory memory,

    /// Its rated reviews, oldest first.
    @Default(<ReviewRecord>[]) List<ReviewRecord> reviews,
  }) = _CardRecord;

  const new _();

  /// Days of stability from which an item counts as recallable.
  static const recallableDays = 7;

  /// Days of stability a durable item needs.
  static const durableDays = 30;

  /// How recent the spaced recall of a durable item must be.
  static const durableWindow = Duration(days: 90);

  /// The least interval that recall must have bridged.
  static const durableGap = Duration(days: 21);

  /// Stability the learner has shown: the one after the latest review with
  /// evidence. Reviews without evidence move the schedule but raise no
  /// level, so that progress rests on evidence alone (I-04).
  double? get shownStability {
    for (final review in reviews.reversed) {
      if (review.evidence) return review.stability;
    }
    return null;
  }

  /// Recalled with a shown stability of a week or more and not forgotten
  /// since.
  bool get isRecallable =>
      memory.state == MemoryState.review &&
      (shownStability ?? 0) >= recallableDays;

  /// Recallable with a month of shown stability, and within
  /// [durableWindow] before [now] a recall on the first try that came at
  /// least [durableGap] after the review before it.
  bool isDurable({required DateTime now}) {
    if (!isRecallable || shownStability! < durableDays) return false;
    final since = now.subtract(durableWindow);
    for (var i = 1; i < reviews.length; i++) {
      final review = reviews[i];
      if (review.unaided &&
          !review.at.isBefore(since) &&
          review.at.difference(reviews[i - 1].at) >= durableGap) {
        return true;
      }
    }
    return false;
  }

  /// The level this card shows at [now]; a card is at least learning.
  ItemLevel level({required DateTime now}) => isDurable(now: now)
      ? ItemLevel.durable
      : isRecallable
      ? ItemLevel.recallable
      : ItemLevel.learning;
}
