import 'dart:async';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/sync/sync_providers.dart';
import 'package:dilbaz_app/data/sync/sync_remote.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:dilbaz_app/features/speaking/application/late_recordings.dart';
import 'package:dilbaz_app/features/sync/application/late_checks.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sync_controller.g.dart';

/// How the device and the server last met: when they were last in step,
/// when the learner's data last changed by it (rows came down, answers
/// were checked late), and what went wrong since, if anything.
typedef SyncStatus = ({
  DateTime? lastSyncAt,
  DateTime? changedAt,
  SyncFailure? failure,
});

/// Keeps the device and the server in step (docs/12-architecture.md §6):
/// when the learner is signed in, when the app comes back, every
/// [period] in the foreground, once local writes have settled for
/// [settle], and when the app leaves the screen.
///
/// Without a connection nothing is lost: the outbox waits for the next
/// time. After a sync, answers that wait for the tutor are checked
/// ([LateChecks]), recordings that wait are processed ([LateRecordings])
/// and recordings' audio goes up (RecordingFiles).
@Riverpod(keepAlive: true)
class SyncController extends _$SyncController {
  static const period = Duration(minutes: 5);
  static const settle = Duration(seconds: 20);

  static const SyncStatus _idle = (
    lastSyncAt: null,
    changedAt: null,
    failure: null,
  );

  Timer? _periodic;
  Timer? _settling;
  Future<void>? _running;
  String? _userId;

  @override
  SyncStatus build() {
    _userId = ref.watch(currentUserIdProvider).value;
    final repository = ref.watch(syncRepositoryProvider);
    ref.onDispose(_stop);
    if (_userId == null) return _idle;
    final writes = repository.watchWaiting().listen((_) => _soon());
    final lifecycle = AppLifecycleListener(
      onResume: () {
        _start();
        unawaited(sync());
      },
      onHide: () {
        _stop();
        unawaited(sync());
      },
    );
    ref.onDispose(() {
      unawaited(writes.cancel());
      lifecycle.dispose();
    });
    _start();
    // After the state is in place.
    unawaited(Future(sync));
    return _idle;
  }

  /// Syncs now; a sync under way is not doubled.
  Future<void> sync() {
    final userId = _userId;
    if (userId == null || !ref.mounted) return Future.value();
    return _running ??= _run(userId).whenComplete(() => _running = null);
  }

  Future<void> _run(String userId) async {
    final result = await ref.read(syncRepositoryProvider).sync(userId);
    if (!ref.mounted) return;
    switch (result) {
      case Ok(value: (pushed: _, :final pulled)):
        final checked = await ref.read(lateChecksProvider).run(userId);
        if (!ref.mounted) return;
        // Recordings that wait are written down and marked (docs/08 §5.2).
        final processed = await ref.read(lateRecordingsProvider).run(userId);
        if (!ref.mounted) return;
        // Recordings' audio goes up once their rows are on the server.
        await ref.read(recordingFilesProvider).uploadWaiting();
        if (!ref.mounted) return;
        final now = ref.read(clockProvider)();
        state = (
          lastSyncAt: now,
          changedAt: pulled + checked + processed > 0 ? now : state.changedAt,
          failure: null,
        );
      case Err(:final error):
        state = (
          lastSyncAt: state.lastSyncAt,
          changedAt: state.changedAt,
          failure: error,
        );
    }
  }

  void _start() {
    _periodic?.cancel();
    _periodic = Timer.periodic(period, (_) => unawaited(sync()));
  }

  void _stop() {
    _periodic?.cancel();
    _settling?.cancel();
  }

  /// A local write: syncs once writes have been quiet for [settle].
  void _soon() {
    _settling?.cancel();
    _settling = Timer(settle, () => unawaited(sync()));
  }
}
