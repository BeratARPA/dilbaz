import 'package:dilbaz_engine/src/fsrs/card_mode.dart';
import 'package:dilbaz_engine/src/planner/plan_card.dart';
import 'package:dilbaz_engine/src/planner/plan_option.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'today_plan.freezed.dart';

/// What the planner suggests for today (docs/05-session-planner.md §1).
/// The learner chooses; nothing in it is mandatory (I-14).
@freezed
abstract class TodayPlan with _$TodayPlan {
  /// Creates a plan.
  const factory({
    /// Time left of the day's budget when the plan was made.
    required Duration budget,

    /// Cards to review, in order.
    @Default(<PlanCard>[]) List<PlanCard> reviews,

    /// Keys of the new items to introduce, in order.
    @Default(<String>[]) List<String> newItems,

    /// Mode of the first card of a new item: spoken, or typed in silent
    /// mode (I-05).
    @Default(CardMode.speak) CardMode newCardMode,

    /// None, or two to three options, the recommended one first.
    @Default(<PlanOption>[]) List<PlanOption> options,

    /// Estimated time of the reviews, the new items and the recommended
    /// option; never more than [budget] (I-13).
    @Default(Duration.zero) Duration estimate,

    /// The budget is used up: enough for today.
    @Default(false) bool enough,

    /// A minimum day: reviews only.
    @Default(false) bool minimumDay,

    /// Longest review block today.
    @Default(Duration.zero) Duration reviewCap,

    /// Average daily review time over the next seven days.
    @Default(Duration.zero) Duration projectedDailyReview,

    /// More reviews are due than fit in today's block; no new items then.
    @Default(false) bool backlog,
  }) = _TodayPlan;
}
