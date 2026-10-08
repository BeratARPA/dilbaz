import 'package:dilbaz_app/app/app.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/gap/gap_providers.dart';
import 'package:dilbaz_app/data/gap/gap_repository.dart';
import 'package:dilbaz_app/data/notifications/notification_gateway.dart';
import 'package:dilbaz_app/data/notifications/notification_providers.dart';
import 'package:dilbaz_app/data/repositories/assessment_repository.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/data/repositories/device_repository.dart';
import 'package:dilbaz_app/data/repositories/drift_profile_repository.dart';
import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';
import 'package:dilbaz_app/data/repositories/placement_bank.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/share/share_providers.dart';
import 'package:dilbaz_app/data/share/shared_text_source.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/data/sync/sync_providers.dart';
import 'package:dilbaz_app/data/sync/sync_remote.dart';
import 'package:dilbaz_app/features/content/application/content_controller.dart';
import 'package:dilbaz_app/features/sync/application/sync_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/card_fixture.dart';
import '../../test/helpers/fake_auth_repository.dart';
import '../../test/helpers/fake_profile_remote.dart';
import '../../test/helpers/fake_profile_repository.dart';
import '../../test/helpers/fake_speech.dart';
import '../../test/helpers/fake_sync_server.dart';
import '../../test/helpers/pack_fixture.dart';
import '../../test/helpers/placement_fixture.dart';
import '../../test/helpers/pump_app.dart';

/// The app on a device for the end-to-end scenarios (docs/15 §4): every
/// screen, controller and repository as it is, the local database on the
/// device's SQLite (in memory), and fakes only for what lies outside the
/// device: auth, the server, the tutor, speech, audio, the system's
/// permissions and notifications.
final class E2eApp {
  /// The first day of a scenario: mid-morning UTC, far from midnight
  /// wherever the phone is.
  static final DateTime firstDay = DateTime.utc(2026, 10, 1, 9);

  /// The app's clock; a scenario moves it on.
  DateTime now = firstDay;

  final AppDatabase db = memoryDatabase();
  final FakeProfileRemote profileRemote = FakeProfileRemote();
  final FakePermissionGateway permissions = FakePermissionGateway();
  final FakeTutorRepository tutor = FakeTutorRepository();
  final FakeSpeechRepository speech = FakeSpeechRepository();
  final FakeSyncServer server = FakeSyncServer();

  /// The placement test on the device; none unless the scenario has one.
  PlacementBank? bank;

  /// While set, the server cannot be reached.
  bool offline = false;

  String get userId => FakeAuthRepository.id;

  DateTime clock() => now;

  /// The welcome flow as if it were done: a profile and its course at
  /// [level]. Without a voice, answers are typed (silent mode).
  Future<void> welcomed({String level = 'A2', bool voice = false}) =>
      DriftProfileRepository(db, profileRemote, now: clock).create(
        userId,
        OnboardingAnswers(
          displayName: 'Berat',
          level: level,
          audioConsent: voice,
          microphone: voice,
        ),
        finished: true,
      );

  /// The app's providers; with [sync], the sync runs against [server].
  List<Override> overrides({required bool sync}) => [
    appDatabaseProvider.overrideWithValue(db),
    authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(signedIn: true),
    ),
    profileRepositoryProvider.overrideWithValue(
      DriftProfileRepository(db, profileRemote, now: clock),
    ),
    teamRepositoryProvider.overrideWithValue(FakeTeamRepository()),
    // The system's dialogs belong to the phone's owner, not to a test.
    permissionGatewayProvider.overrideWithValue(permissions),
    notificationGatewayProvider.overrideWithValue(
      const NoNotificationGateway(),
    ),
    // Every repository stamps its rows with the scenario's clock.
    assessmentRepositoryProvider.overrideWithValue(
      DriftAssessmentRepository(db, now: clock),
    ),
    cardRepositoryProvider.overrideWithValue(
      DriftCardRepository(db, now: clock),
    ),
    gapRepositoryProvider.overrideWithValue(DriftGapRepository(db, now: clock)),
    deviceRepositoryProvider.overrideWithValue(
      DriftDeviceRepository(db, now: clock),
    ),
    placementBankRepositoryProvider.overrideWithValue(FakeBankRepository(bank)),
    // The packs are installed by the scenario.
    contentControllerProvider.overrideWithBuild(
      (ref, notifier) => readyContent,
    ),
    syncRemoteProvider.overrideWithValue(_Line(this, server.remoteFor(userId))),
    if (!sync)
      syncControllerProvider.overrideWithBuild(
        (ref, notifier) => (lastSyncAt: null, changedAt: null, failure: null),
      ),
    packAudioProvider.overrideWithValue(FakePackAudio()),
    clipPlayerProvider.overrideWithValue(FakeClipPlayer()),
    answerRecorderProvider.overrideWithValue(FakeAnswerRecorder()),
    speechRepositoryProvider.overrideWithValue(speech),
    dictationProvider.overrideWithValue(FakeDictation()),
    sharedTextSourceProvider.overrideWithValue(const NoSharedTextSource()),
    ...cardDataOverrides(db: db, tutor: tutor, clock: clock),
  ];

  /// Opens the app, as the learner does each day. The database outlives
  /// it, so the app can be opened again on a later day.
  Future<void> open(WidgetTester tester, {bool sync = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(sync: sync),
        child: const DilbazApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Closes the app.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }
}

/// The server as the device reaches it: out of reach while the app is
/// [E2eApp.offline].
final class _Line implements SyncRemote {
  new(this._app, this._server);

  final E2eApp _app;
  final SyncRemote _server;

  @override
  Future<Result<PushResult, SyncFailure>> push(
    String deviceId,
    Map<String, Object?> batch,
  ) async => _app.offline
      ? const Err(SyncFailure.network)
      : await _server.push(deviceId, batch);

  @override
  Future<Result<PullPage, SyncFailure>> pull(
    int since, {
    required int limit,
  }) async => _app.offline
      ? const Err(SyncFailure.network)
      : await _server.pull(since, limit: limit);
}

/// On a device the app works in real time: a step waits for what it needs
/// instead of expecting it after one frame.
extension E2eSteps on WidgetTester {
  static const _patience = Duration(seconds: 20);
  static const _step = Duration(milliseconds: 100);

  /// Pumps frames until [done], failing after a while with what the
  /// screen shows.
  Future<void> waitUntil(bool Function() done, {String? what}) async {
    final stopwatch = Stopwatch()..start();
    while (!done()) {
      if (stopwatch.elapsed > _patience) {
        final shown = [
          for (final widget in allWidgets)
            if (widget is RichText && !_isIcon(widget.text.toPlainText()))
              widget.text.toPlainText()
            else if ('${widget.runtimeType}'.endsWith('Screen') ||
                '${widget.runtimeType}'.endsWith('Page'))
              '<${widget.runtimeType}>',
        ];
        throw TestFailure(
          'Waited $_patience for ${what ?? 'a condition'}. '
          'On the screen: ${shown.join(' | ')}',
        );
      }
      await pump(_step);
    }
  }

  /// Pumps frames until [finder] finds something.
  Future<void> waitFor(Finder finder) =>
      waitUntil(() => finder.evaluate().isNotEmpty, what: '$finder');

  /// Pumps frames until one of [texts] shows, and says which.
  Future<String> waitForOneOf(List<String> texts) async {
    String? shown() {
      for (final text in texts) {
        if (find.text(text).evaluate().isNotEmpty) return text;
      }
      return null;
    }

    await waitUntil(() => shown() != null, what: texts.join(' | '));
    return shown()!;
  }

  /// Taps the last widget showing [text] once it shows, scrolled into
  /// view first.
  Future<void> tapText(String text) async {
    // A focused field scrolls itself back into view; let it go first.
    FocusManager.instance.primaryFocus?.unfocus();
    await waitFor(find.text(text));
    await ensureVisible(find.text(text).last);
    await pumpAndSettle();
    await tap(find.text(text).last);
    await pumpAndSettle();
  }

  /// Types [text] into the first field, or the one labelled [label].
  Future<void> write(String text, {String? label}) async {
    final field = label == null
        ? find.byType(TextField).first
        : find.widgetWithText(TextField, label);
    await waitFor(field);
    // Focused by a tap, as the learner does: the binding asks for the
    // keyboard only for a field it has not focused before.
    await tap(field);
    await pump();
    await enterText(field, text);
    await pumpAndSettle();
  }
}

/// An icon's glyph, from the private use area.
bool _isIcon(String text) =>
    text.runes.every((rune) => rune >= 0xE000 && rune <= 0xF8FF);
