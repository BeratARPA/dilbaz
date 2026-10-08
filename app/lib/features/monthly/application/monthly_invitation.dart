import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:dilbaz_app/features/placement/application/placement_invitation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'monthly_invitation.g.dart';

/// Days of the month the test is invited on (docs/05 §6).
const monthlyInvitationDays = 7;

/// Whether this month's speaking test is open: days 1–7 where the learner
/// is, none taken this month, and the anchors on the device.
@riverpod
Future<bool> monthlyOpen(Ref ref) async {
  final userId = await ref.watch(currentUserIdProvider.future);
  if (userId == null) return false;
  final local = ref.watch(clockProvider)().toLocal();
  if (local.day > monthlyInvitationDays) return false;
  final course = await ref.watch(assessmentRepositoryProvider).course(userId);
  if (course == null) return false;
  final taken = await ref
      .watch(monthlyTestRepositoryProvider)
      .takenSince(course.id, DateTime(local.year, local.month).toUtc());
  if (taken) return false;
  final tasks = await ref.watch(taskContentRepositoryProvider).speakingTasks();
  return tasks.any((task) => task.anchor != null);
}

/// The invitation was put aside; it comes back on the next start. Putting
/// it aside has no other consequence (I-14).
@Riverpod(keepAlive: true)
class MonthlyInvitationDismissed extends _$MonthlyInvitationDismissed {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

/// Whether Today invites the learner to this month's test; the placement
/// test comes first.
@riverpod
bool monthlyInvited(Ref ref) =>
    !ref.watch(monthlyInvitationDismissedProvider) &&
    !ref.watch(placementInvitedProvider) &&
    (ref.watch(monthlyOpenProvider).value ?? false);
