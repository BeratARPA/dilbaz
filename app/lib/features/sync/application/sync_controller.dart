import 'dart:async';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/sync/sync_providers.dart';
import 'package:dilbaz_app/data/sync/sync_remote.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sync_controller.g.dart';

/// How the device and the server last met: when they were last in step,
/// when rows last came down, and what went wrong since, if anything.
typedef SyncStatus = ({
  DateTime? lastSyncAt,
  DateTime? pulledAt,
  SyncFailure? failure,
});

/// Keeps the device and the server in step (docs/12-architecture.md §6):
/// when the learner is signed in, when the app comes back, every
/// [period] in the foreground, once local writes have settled for
/// [settle], and when the app leaves the screen.
///
/// Without a connection nothing is lost: the outbox waits for the next
/// time.
@Riverpod(keepAlive: true)
class SyncController extends _$SyncController {
  static const period = Duration(minutes: 5);
  static const settle = Duration(seconds: 20);

  static const SyncStatus _idle = (
    lastSyncAt: null,
    pulledAt: null,
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
    final now = ref.read(clockProvider)();
    state = switch (result) {
      Ok(value: (pushed: _, :final pulled)) => (
        lastSyncAt: now,
        pulledAt: pulled > 0 ? now : state.pulledAt,
        failure: null,
      ),
      Err(:final error) => (
        lastSyncAt: state.lastSyncAt,
        pulledAt: state.pulledAt,
        failure: error,
      ),
    };
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
