import 'package:dilbaz_app/features/gap_journal/presentation/gap_capture_screen.dart';
import 'package:dilbaz_app/features/practice/presentation/practice_screen.dart';
import 'package:dilbaz_app/features/progress/presentation/progress_screen.dart';
import 'package:dilbaz_app/features/settings/presentation/settings_screen.dart';
import 'package:dilbaz_app/features/today/presentation/today_screen.dart';
import 'package:dilbaz_app/features/together/presentation/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  final captureButton = find.widgetWithText(
    FloatingActionButton,
    trStrings.gapCaptureButton,
  );

  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('opens on the Today tab with four tabs', (tester) async {
    await tester.pumpDilbazApp();

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final label in [
      trStrings.tabToday,
      trStrings.tabPractice,
      trStrings.tabTogether,
      trStrings.tabProgress,
    ]) {
      expect(tab(label), findsOneWidget);
    }
  });

  testWidgets('every tab shows its screen and the capture button', (
    tester,
  ) async {
    await tester.pumpDilbazApp();

    final screens = {
      trStrings.tabPractice: PracticeScreen,
      trStrings.tabTogether: TogetherScreen,
      trStrings.tabProgress: ProgressScreen,
      trStrings.tabToday: TodayScreen,
    };
    for (final MapEntry(key: label, value: screen) in screens.entries) {
      await tester.tap(tab(label));
      await tester.pumpAndSettle();
      expect(find.byType(screen), findsOneWidget, reason: label);
      expect(captureButton, findsOneWidget, reason: label);
    }
  });

  testWidgets('the capture button opens the capture page over the tabs', (
    tester,
  ) async {
    await tester.pumpDilbazApp();

    await tester.tap(captureButton);
    await tester.pumpAndSettle();
    expect(find.byType(GapCaptureScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // pageBack() looks for an English "Back" tooltip; the UI is Turkish.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('settings open from the Progress tab', (tester) async {
    await tester.pumpDilbazApp();

    await tester.tap(tab(trStrings.tabProgress));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(trStrings.settingsTitle));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
