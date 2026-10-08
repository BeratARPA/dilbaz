import 'dart:convert';
import 'dart:typed_data';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/my_data/my_data_providers.dart';
import 'package:dilbaz_app/data/my_data/my_data_remote.dart';
import 'package:dilbaz_app/data/my_data/my_data_repository.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/settings_change.dart';
import 'package:dilbaz_app/data/share/file_sharer.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:dilbaz_app/features/settings/application/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

/// The learner's data in memory: what was exported and deleted.
final class FakeMyDataRepository implements MyDataRepository {
  MyDataFailure? failure;
  final deleted = <String>[];

  @override
  Future<Map<String, Object?>> export(
    String userId, {
    required DateTime at,
  }) async => {'profile_id': userId, 'exported_at': at.toIso8601String()};

  @override
  Future<Result<void, MyDataFailure>> deleteAll(String userId) async {
    final failure = this.failure;
    if (failure != null) return Err(failure);
    deleted.add(userId);
    return const Ok(null);
  }
}

/// The share sheet: what was handed to it.
final class FakeFileSharer implements FileSharer {
  bool shares = true;
  final shared = <({String name, String mimeType, Uint8List bytes})>[];

  @override
  Future<bool> share({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    shared.add((name: name, mimeType: mimeType, bytes: bytes));
    return shares;
  }
}

void main() {
  late FakeProfileRepository profiles;
  late FakePermissionGateway permissions;
  late FakeMyDataRepository data;
  late FakeFileSharer sharer;
  late ProviderContainer container;

  setUp(() {
    profiles = FakeProfileRepository(onboarded: true);
    permissions = FakePermissionGateway();
    data = FakeMyDataRepository();
    sharer = FakeFileSharer();
    container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith(
          (ref) => Stream.value(FakeAuthRepository.id),
        ),
        profileRepositoryProvider.overrideWithValue(profiles),
        permissionGatewayProvider.overrideWithValue(permissions),
        myDataRepositoryProvider.overrideWithValue(data),
        fileSharerProvider.overrideWithValue(sharer),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 8, 9)),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<SettingsController> controller() async {
    container.listen(settingsControllerProvider, (_, _) {});
    await container.read(currentUserIdProvider.future);
    await container.read(settingsControllerProvider.future);
    final notifier = container.read(settingsControllerProvider.notifier);
    // The profile's stream listens for changes from here on.
    await pumpEventQueue();
    return notifier;
  }

  test('the settings show as the profile has them, and change', () async {
    final settings = await controller();
    expect(container.read(settingsControllerProvider).value, profiles.settings);
    expect(
      await settings.change(const SettingsChange.budget(45)),
      SettingsOutcome.done,
    );
    expect(profiles.changes, [const SettingsChange.budget(45)]);
    await pumpEventQueue();
    expect(container.read(settingsControllerProvider).value!.timeBudgetMin, 45);
  });

  test('the invitation goes on only with the permission to notify', () async {
    final settings = await controller();
    permissions.notifications = false;
    expect(
      await settings.change(const SettingsChange.invitation(wanted: true)),
      SettingsOutcome.permissionDenied,
    );
    expect(profiles.changes, isEmpty);

    permissions.notifications = true;
    expect(
      await settings.change(const SettingsChange.invitation(wanted: true)),
      SettingsOutcome.done,
    );
    // Turning it off asks for nothing.
    await settings.change(const SettingsChange.invitation(wanted: false));
    expect(permissions.asked, ['notifications', 'notifications']);
    expect(profiles.changes, hasLength(2));
  });

  test(
    'audio consent is saved even when the microphone is not allowed',
    () async {
      final settings = await controller();
      permissions.microphone = false;
      expect(
        await settings.change(const SettingsChange.audioConsent(granted: true)),
        SettingsOutcome.permissionDenied,
      );
      expect(profiles.changes, [
        const SettingsChange.audioConsent(granted: true),
      ]);
      await settings.change(const SettingsChange.audioConsent(granted: false));
      expect(permissions.asked, ['microphone']);
    },
  );

  test('the export goes to the share sheet as a dated JSON file', () async {
    final settings = await controller();
    expect(await settings.export(), isTrue);
    final file = sharer.shared.single;
    expect(file.name, 'dilbaz-2026-10-08.json');
    expect(file.mimeType, 'application/json');
    expect(jsonDecode(utf8.decode(file.bytes)), {
      'profile_id': FakeAuthRepository.id,
      'exported_at': '2026-10-08T09:00:00.000Z',
    });
    sharer.shares = false;
    expect(await settings.export(), isFalse);
  });

  test('deleting all: done, offline or failed', () async {
    final settings = await controller();
    expect(await settings.deleteAll(), SettingsOutcome.done);
    expect(data.deleted, [FakeAuthRepository.id]);
    data.failure = MyDataFailure.network;
    expect(await settings.deleteAll(), SettingsOutcome.offline);
    data.failure = MyDataFailure.unknown;
    expect(await settings.deleteAll(), SettingsOutcome.failed);
  });
}
