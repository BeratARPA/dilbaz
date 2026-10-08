import 'dart:math';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_app/features/sync/application/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'today_controller.freezed.dart';
part 'today_controller.g.dart';

/// The greeting by the hour where the learner is; no streak (docs/09 §5.2).
enum TodayGreeting {
  morning,
  day,
  evening;

  factory of(DateTime now) => switch (now.toLocal().hour) {
    >= 5 && < 11 => morning,
    >= 11 && < 18 => day,
    _ => evening,
  };
}

/// What the Today screen shows (docs/09 §5.2): the planner's cards for the
/// time left, the week so far, and "enough for today" when the time is up.
@freezed
abstract class TodayView with _$TodayView {
  const factory({
    required TodayGreeting greeting,

    /// The day's budget, and what the learner said they have today; null
    /// means the budget.
    required Duration dailyBudget,

    /// Cards planned now and their time.
    required int reviews,
    required int newItems,
    required Duration estimate,

    /// The day's time is used up: "Bugünlük yeter" (docs/09 §5.14).
    required bool enough,

    /// A short day: reviews only (docs/05 §3, line 9).
    required bool minimumDay,

    /// More reviews are due than fit today: no new items.
    required bool backlog,

    /// Today so far.
    required int reviewedToday,
    required int introducedToday,
    required Duration spentToday,

    /// Days studied this week, and the learner's weekly goal.
    required int daysThisWeek,
    required int weeklyGoal,
    Duration? chosen,

    /// The learner's habit anchor, for "see you tomorrow".
    String? anchor,
  }) = _TodayView;
}

/// The Today screen's view; null before the welcome flow or the packs.
@riverpod
Future<TodayView?> today(Ref ref) async {
  // Rows from another device, or answers checked late, change the day.
  ref.watch(syncControllerProvider.select((status) => status.changedAt));
  final planned = await planCards(ref);
  if (planned == null) return null;
  final now = ref.watch(clockProvider)();
  final chosen = ref.watch(todayTimeProvider);
  final cards = ref.watch(cardRepositoryProvider);
  final sessions = ref.watch(sessionRepositoryProvider);
  final day = startOfLocalDay(now);
  final courseId = planned.course.id;
  final plan = planned.plan;
  // A new item's first review is part of its introduction.
  final reviewed = await cards.reviewsSince(courseId, day) - planned.newToday;
  return TodayView(
    greeting: TodayGreeting.of(now),
    dailyBudget: planned.settings.dailyBudget,
    chosen: chosen != null && chosen.day == day ? chosen.available : null,
    reviews: plan.reviews.length,
    newItems: plan.newItems.length,
    estimate: plan.estimate,
    enough: plan.enough,
    minimumDay: plan.minimumDay,
    backlog: plan.backlog,
    reviewedToday: max(0, reviewed),
    introducedToday: planned.newToday,
    spentToday: planned.spentToday,
    daysThisWeek: (await sessions.daysSince(
      courseId,
      startOfLocalWeek(now),
    )).length,
    weeklyGoal: planned.settings.weeklyDaysGoal,
    anchor: planned.settings.anchor,
  );
}
