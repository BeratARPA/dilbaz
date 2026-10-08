import 'dart:convert';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/my_data/my_data_providers.dart';
import 'package:dilbaz_app/data/my_data/my_data_remote.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/settings_change.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_controller.g.dart';

/// How a request of the Settings screen ended.
enum SettingsOutcome {
  done,

  /// Saved, but the system's permission it needs was not given.
  permissionDenied,

  /// The server could not be reached.
  offline,
  failed,
}

/// The Settings screen (docs/09-ux-motivation.md §5.12): the learner's
/// settings as they change, each change saved on its own and synced, and
/// the learner's data rights (docs/14 §4).
@riverpod
class SettingsController extends _$SettingsController {
  @override
  Stream<ProfileSettings?> build() {
    final userId = ref.watch(currentUserIdProvider).value;
    if (userId == null) return Stream.value(null);
    return ref.watch(profileRepositoryProvider).watchSettings(userId);
  }

  /// Saves [change]. The daily invitation goes on only with the system's
  /// permission to notify; audio consent is the learner's own, the
  /// microphone the system's, so it is saved either way.
  Future<SettingsOutcome> change(SettingsChange change) async {
    final userId = ref.read(currentUserIdProvider).value;
    if (userId == null) return SettingsOutcome.failed;
    final permissions = ref.read(permissionGatewayProvider);
    final profiles = ref.read(profileRepositoryProvider);
    if (change case InvitationChange(wanted: true)) {
      if (!await permissions.requestNotifications()) {
        return SettingsOutcome.permissionDenied;
      }
    }
    await profiles.changeSettings(userId, change);
    if (change case AudioConsentChange(granted: true)) {
      if (!await permissions.requestMicrophone()) {
        return SettingsOutcome.permissionDenied;
      }
    }
    return SettingsOutcome.done;
  }

  /// "Verilerimi dışa aktar": everything as one JSON file, to the share
  /// sheet. False when the learner closed it.
  Future<bool> export() async {
    final userId = ref.read(currentUserIdProvider).value;
    if (userId == null) return false;
    final now = ref.read(clockProvider)();
    final data = await ref
        .read(myDataRepositoryProvider)
        .export(userId, at: now);
    final day = now.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return await ref
        .read(fileSharerProvider)
        .share(
          name: 'dilbaz-${day.year}-${two(day.month)}-${two(day.day)}.json',
          mimeType: 'application/json',
          bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
        );
  }

  /// "Tüm verimi sil": everything of the learner, on the server and here.
  /// The welcome flow follows, since there is no profile any more.
  Future<SettingsOutcome> deleteAll() async {
    final userId = ref.read(currentUserIdProvider).value;
    if (userId == null) return SettingsOutcome.failed;
    return switch (await ref.read(myDataRepositoryProvider).deleteAll(userId)) {
      Ok() => SettingsOutcome.done,
      Err(error: MyDataFailure.network) => SettingsOutcome.offline,
      Err() => SettingsOutcome.failed,
    };
  }
}
