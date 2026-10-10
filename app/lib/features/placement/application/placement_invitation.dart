import 'package:dilbaz_app/core/config/course_defaults.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'placement_invitation.g.dart';

/// Whether the content on the device holds a placement test.
@riverpod
Stream<bool> placementAvailable(Ref ref) =>
    ref.watch(placementBankRepositoryProvider).watchAvailable(defaultL2);

/// Whether the learner's course has no placement test yet.
@riverpod
Stream<bool> placementOpen(Ref ref) {
  final userId = ref.watch(currentUserIdProvider).value;
  if (userId == null) return Stream.value(false);
  return ref.watch(assessmentRepositoryProvider).watchPlacementOpen(userId);
}

/// The invitation was put aside; it comes back on the next start. Putting
/// it aside has no other consequence (I-14).
@Riverpod(keepAlive: true)
class PlacementInvitationDismissed extends _$PlacementInvitationDismissed {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

/// Whether Today invites the learner to the placement test.
@riverpod
bool placementInvited(Ref ref) =>
    !ref.watch(placementInvitationDismissedProvider) &&
    (ref.watch(placementOpenProvider).value ?? false) &&
    (ref.watch(placementAvailableProvider).value ?? false);
