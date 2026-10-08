import 'package:dilbaz_app/data/my_data/my_data_providers.dart';
import 'package:dilbaz_app/data/my_data/my_data_remote.dart';
import 'package:dilbaz_app/data/repositories/settings_change.dart';
import 'package:dilbaz_app/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/pump_app.dart';
import 'settings_controller_test.dart'
    show FakeFileSharer, FakeMyDataRepository;

void main() {
  late FakeProfileRepository profiles;
  late FakePermissionGateway permissions;
  late FakeMyDataRepository data;
  late FakeFileSharer sharer;

  setUp(() {
    profiles = FakeProfileRepository(onboarded: true);
    permissions = FakePermissionGateway();
    data = FakeMyDataRepository();
    sharer = FakeFileSharer();
  });

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpDilbazApp(
      profiles: profiles,
      permissions: permissions,
      extra: [
        myDataRepositoryProvider.overrideWithValue(data),
        fileSharerProvider.overrideWithValue(sharer),
      ],
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(trStrings.tabProgress),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(trStrings.settingsTitle));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  testWidgets('each change is saved at once', (tester) async {
    await openSettings(tester);
    await tapText(tester, trStrings.onboardingBudgetMinutes(45));
    await tapText(tester, trStrings.onboardingWeeklyDays(6));
    await tapText(tester, trStrings.anchorLunchBreak);
    await tapText(tester, trStrings.settingsSilentMode);
    await tapText(tester, trStrings.onboardingAiConsent);
    await tapText(tester, trStrings.settingsQuietHours);
    expect(profiles.changes, const [
      SettingsChange.budget(45),
      SettingsChange.daysGoal(6),
      SettingsChange.anchor(anchor: 'lunch_break', time: '12:30'),
      SettingsChange.silentMode(on: true),
      SettingsChange.aiDataConsent(granted: true),
      SettingsChange.quietHours((from: '22:30', to: '08:00')),
    ]);
    // The quiet hours show their ends.
    expect(find.text(trStrings.settingsQuietFrom('22:30')), findsOneWidget);
    expect(find.text(trStrings.settingsQuietTo('08:00')), findsOneWidget);
  });

  testWidgets('without the permission to notify, the invitation stays off', (
    tester,
  ) async {
    permissions.notifications = false;
    await openSettings(tester);
    await tapText(tester, trStrings.settingsInvitation);
    expect(profiles.changes, isEmpty);
    expect(find.text(trStrings.settingsNotificationsDenied), findsOneWidget);
  });

  testWidgets('the export goes to the share sheet', (tester) async {
    await openSettings(tester);
    await tapText(tester, trStrings.settingsExport);
    expect(sharer.shared.single.name, endsWith('.json'));
  });

  testWidgets('deleting all asks first, and says when it needs a connection', (
    tester,
  ) async {
    await openSettings(tester);
    await tapText(tester, trStrings.settingsDeleteAll);
    expect(find.text(trStrings.settingsDeleteBody), findsOneWidget);
    await tapText(tester, trStrings.settingsDeleteCancel);
    expect(data.deleted, isEmpty);

    data.failure = MyDataFailure.network;
    await tapText(tester, trStrings.settingsDeleteAll);
    await tapText(tester, trStrings.settingsDeleteConfirm);
    expect(find.text(trStrings.settingsOffline), findsOneWidget);

    data.failure = null;
    await tapText(tester, trStrings.settingsDeleteAll);
    await tapText(tester, trStrings.settingsDeleteConfirm);
    expect(data.deleted, [FakeAuthRepository.id]);
  });

  testWidgets('every part fits a small phone at double text size', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final handle = tester.ensureSemantics();
    profiles.settings = (
      timeBudgetMin: 30,
      weeklyDaysGoal: 5,
      anchor: 'morning_coffee',
      anchorTime: '08:30',
      dailyInvitation: true,
      quietHours: (from: '22:30', to: '08:00'),
      silentMode: false,
      audioConsent: true,
      aiDataConsent: false,
    );
    await openSettings(tester);
    for (final text in [
      trStrings.onboardingAnchorTitle,
      trStrings.settingsQuietTo('08:00'),
      trStrings.onboardingAiConsent,
      trStrings.settingsDeleteAll,
      trStrings.signOut,
    ]) {
      await tester.ensureVisible(find.text(text));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    }
    handle.dispose();
  });
}
