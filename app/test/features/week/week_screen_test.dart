import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/session_repository.dart';
import 'package:dilbaz_app/features/week/presentation/week_screen.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../../helpers/pump_app.dart';

void main() {
  late AppDatabase db;

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  /// The app at [now], with a 12-minute card session at [studied].
  Future<void> open(
    WidgetTester tester, {
    DateTime? now,
    DateTime? studied,
  }) async {
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
      if (studied != null) {
        await DriftSessionRepository(db).record(
          userId: FakeAuthRepository.id,
          courseId: FakeAssessmentRepository.zzCourse.id,
          deviceId: 'device-1',
          startedAt: studied,
          endedAt: studied.add(const Duration(minutes: 12)),
          strands: {Strand.language: const Duration(minutes: 12)},
        );
      }
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      db: db,
      extra: cardDataOverrides(
        db: db,
        tutor: FakeTutorRepository(),
        clock: now == null ? null : () => now,
      ),
    );
  }

  testWidgets('from Progress: this week in counts, then last week', (
    tester,
  ) async {
    // cardNow is a Thursday; the session is on its Tuesday.
    await open(tester, studied: DateTime.utc(2026, 9, 29, 9));
    await tapText(tester, trStrings.tabProgress);
    await tapText(tester, trStrings.weekTitle);
    expect(find.byType(WeekScreen), findsOneWidget);
    expect(find.text(trStrings.weekDays(1, 5)), findsOneWidget);
    expect(find.text(trStrings.weekTime(12)), findsOneWidget);
    expect(find.text(trStrings.weekStrandLanguage(12)), findsOneWidget);

    await tapText(tester, trStrings.weekLast);
    expect(find.text(trStrings.weekNothing), findsOneWidget);
  });

  testWidgets("a new week's first opening offers last week's summary", (
    tester,
  ) async {
    await open(
      tester,
      now: DateTime.utc(2026, 10, 5, 12),
      studied: DateTime.utc(2026, 9, 30, 9),
    );
    await tapText(tester, trStrings.todayLastWeekSummary);
    expect(find.byType(WeekScreen), findsOneWidget);
    final last = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(last.selected, {true});
    expect(find.text(trStrings.weekDays(1, 5)), findsOneWidget);
  });

  testWidgets('no offer in the middle of a week', (tester) async {
    await open(tester, studied: DateTime.utc(2026, 9, 29, 9));
    expect(find.text(trStrings.todayWeekSummary), findsNothing);
    expect(find.text(trStrings.todayLastWeekSummary), findsNothing);
  });

  testWidgets('fits a small phone at double text size', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final handle = tester.ensureSemantics();
    await open(tester, studied: DateTime.utc(2026, 9, 29, 9));
    await tapText(tester, trStrings.tabProgress);
    await tapText(tester, trStrings.weekTitle);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
