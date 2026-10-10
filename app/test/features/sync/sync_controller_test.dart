import 'dart:async';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/sync/sync_providers.dart';
import 'package:dilbaz_app/data/sync/sync_remote.dart';
import 'package:dilbaz_app/data/sync/sync_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_files.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:dilbaz_app/features/sync/application/late_checks.dart';
import 'package:dilbaz_app/features/sync/application/sync_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const userId = '11111111-1111-4111-8111-111111111111';
final t0 = DateTime.utc(2026, 10, 1, 9);

final class FakeSyncRepository implements SyncRepository {
  final waiting = StreamController<void>.broadcast();
  final runs = <String>[];
  Result<SyncReport, SyncFailure> next = const Ok((pushed: 0, pulled: 0));

  /// While set, a sync waits for it.
  Completer<void>? hold;

  @override
  Future<Result<SyncReport, SyncFailure>> sync(String userId) async {
    runs.add(userId);
    await hold?.future;
    return next;
  }

  @override
  Stream<void> watchWaiting() => waiting.stream;
}

/// Late checks that settle as many answers as told.
final class FakeLateChecks implements LateChecks {
  int settles = 0;
  final runs = <String>[];

  @override
  Future<int> run(String userId) async {
    runs.add(userId);
    return settles;
  }
}

/// Recordings' audio that counts its uploads.
final class FakeRecordingFiles implements RecordingFiles {
  int uploads = 0;

  @override
  Future<int> uploadWaiting() async => uploads++;

  @override
  Future<String?> playable(String audioPath) async => null;
}

void main() {
  late FakeSyncRepository repository;
  late FakeRecordingFiles files;
  late FakeLateChecks checks;
  late ProviderContainer container;

  /// The controller kept alive, with [signedIn] the learner's id.
  Future<void> start(WidgetTester tester, {String? signedIn = userId}) async {
    repository = FakeSyncRepository();
    checks = FakeLateChecks();
    files = FakeRecordingFiles();
    container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => Stream.value(signedIn)),
        syncRepositoryProvider.overrideWithValue(repository),
        lateChecksProvider.overrideWithValue(checks),
        recordingFilesProvider.overrideWithValue(files),
        clockProvider.overrideWithValue(() => t0),
      ],
    )..listen(syncControllerProvider, (_, _) {});
    // The user id arrives, the controller rebuilds (Riverpod schedules
    // that with a timer), and its first sync runs after that.
    for (var turn = 0; turn < 3; turn++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  SyncStatus status() => container.read(syncControllerProvider);

  /// Steps the app's lifecycle one state at a time, as a device does.
  void lifecycle(WidgetTester tester, List<AppLifecycleState> states) =>
      states.forEach(tester.binding.handleAppLifecycleStateChanged);

  testWidgets('syncs once signed in, then every five minutes', (tester) async {
    await start(tester);
    expect(repository.runs, [userId]);

    await tester.pump(const Duration(minutes: 4));
    expect(repository.runs, hasLength(1));
    await tester.pump(const Duration(minutes: 1));
    expect(repository.runs, hasLength(2));
    container.dispose();
  });

  testWidgets('local writes sync once they settle', (tester) async {
    await start(tester);
    repository.waiting.add(null);
    await tester.pump(const Duration(seconds: 10));
    repository.waiting.add(null);
    await tester.pump(const Duration(seconds: 10));
    expect(repository.runs, hasLength(1));
    await tester.pump(const Duration(seconds: 10));
    expect(repository.runs, hasLength(2));
    container.dispose();
  });

  testWidgets('leaving the screen syncs and stops the clock; coming back '
      'syncs and starts it again', (tester) async {
    await start(tester);
    lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.hidden]);
    await tester.pump();
    expect(repository.runs, hasLength(2));
    lifecycle(tester, [AppLifecycleState.paused]);
    await tester.pump(const Duration(minutes: 10));
    expect(repository.runs, hasLength(2));

    lifecycle(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await tester.pump();
    expect(repository.runs, hasLength(3));
    await tester.pump(SyncController.period);
    expect(repository.runs, hasLength(4));
    container.dispose();
  });

  testWidgets('a sync under way is not doubled', (tester) async {
    await start(tester);
    final hold = repository.hold = Completer<void>();
    final controller = container.read(syncControllerProvider.notifier);
    final first = controller.sync();
    final second = controller.sync();
    expect(repository.runs, hasLength(2));
    hold.complete();
    await tester.pump();
    await first;
    await second;
    await controller.sync();
    expect(repository.runs, hasLength(3));
    container.dispose();
  });

  testWidgets('the status tells when the device was in step and when the '
      "learner's data changed", (tester) async {
    await start(tester);
    expect(status(), (lastSyncAt: t0, changedAt: null, failure: null));
    expect(checks.runs, [userId]);

    repository.next = const Ok((pushed: 0, pulled: 3));
    await container.read(syncControllerProvider.notifier).sync();
    expect(status(), (lastSyncAt: t0, changedAt: t0, failure: null));

    repository.next = const Err(SyncFailure.network);
    await container.read(syncControllerProvider.notifier).sync();
    expect(status(), (
      lastSyncAt: t0,
      changedAt: t0,
      failure: SyncFailure.network,
    ));
    // Without a sync, nothing goes to the tutor or the server's audio.
    expect(checks.runs, hasLength(2));
    expect(files.uploads, 2);
    container.dispose();
  });

  testWidgets('answers checked late change the data too', (tester) async {
    await start(tester);
    checks.settles = 2;
    await container.read(syncControllerProvider.notifier).sync();
    expect(status().changedAt, t0);
    container.dispose();
  });

  testWidgets('signed out, nothing syncs', (tester) async {
    await start(tester, signedIn: null);
    await tester.pump(const Duration(minutes: 10));
    await container.read(syncControllerProvider.notifier).sync();
    expect(repository.runs, isEmpty);
    container.dispose();
  });
}
