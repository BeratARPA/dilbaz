import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_app/data/repositories/week_repository.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_app/features/sync/application/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'week_summary.g.dart';

/// A week's summary (docs/09 §5.13): the learner's local days from Monday,
/// what was done in them, and their weekly goal. "Last" is the week before
/// this one; this week runs up to now.
typedef WeekSummary = ({
  bool last,

  /// Its Monday and its last day so far, where the learner is.
  DateTime from,
  DateTime to,
  WeekActivity activity,
  int weeklyGoal,
});

/// The summary of this week, or of [last] week; null before the welcome
/// flow.
@riverpod
Future<WeekSummary?> weekSummary(Ref ref, {bool last = false}) async {
  ref.watch(syncControllerProvider.select((status) => status.changedAt));
  final userId = ref.watch(authRepositoryProvider).userId;
  if (userId == null) return null;
  final course = await ref.watch(assessmentRepositoryProvider).course(userId);
  final settings = await ref
      .watch(profileRepositoryProvider)
      .studySettings(userId);
  if (course == null || settings == null) return null;
  final now = ref.watch(clockProvider)();
  final monday = startOfLocalWeek(now);
  final start = last ? startOfLocalWeek(monday.subtract(_day)) : monday;
  final end = last ? monday : now;
  final local = end.subtract(const Duration(microseconds: 1)).toLocal();
  return (
    last: last,
    from: start.toLocal(),
    to: DateTime(local.year, local.month, local.day),
    activity: await ref
        .watch(weekRepositoryProvider)
        .week(course.id, start, end),
    weeklyGoal: settings.weeklyDaysGoal,
  );
}

const _day = Duration(days: 1);

/// Which summary the Today screen offers (docs/09 §5.13): this week's on
/// Sunday once something was done, last week's on a new week's first
/// opening before anything is done; none otherwise.
enum WeekSummaryOffer { thisWeek, lastWeek }

/// The offer for [now], given the days studied this week and last week.
WeekSummaryOffer? weekSummaryOffer({
  required DateTime now,
  required int daysThisWeek,
  required int daysLastWeek,
}) {
  if (now.toLocal().weekday == DateTime.sunday && daysThisWeek > 0) {
    return WeekSummaryOffer.thisWeek;
  }
  if (daysThisWeek == 0 && daysLastWeek > 0) return WeekSummaryOffer.lastWeek;
  return null;
}
