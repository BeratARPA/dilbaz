import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/features/shadowing/presentation/shadowing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../../helpers/pump_app.dart';
import '../dictation_practice/dictation_practice_controller_test.dart'
    show understood;
import 'shadowing_controller_test.dart' show heardAs;

void main() {
  late AppDatabase db;
  late FakeTutorRepository tutor;

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool known = true}) async {
    final assessments = FakeAssessmentRepository(open: false);
    tutor = FakeTutorRepository()..heard = heardAs([(1, 'kolu', 'zz.phon.a')]);
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
      if (known) await understood(db, assessments);
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      db: db,
      assessments: assessments,
      extra: cardDataOverrides(db: db, tutor: tutor),
    );
    await tapText(tester, trStrings.tabPractice);
    await tapText(tester, trStrings.practiceShadowingTitle);
  }

  testWidgets('nothing the learner can follow yet: it says why', (
    tester,
  ) async {
    await open(tester, known: false);
    expect(find.byType(ShadowingScreen), findsOneWidget);
    expect(find.text(trStrings.shadowingNothingToSay), findsOneWidget);
  });

  testWidgets('hear, say, see the sounds to work on, once more, the end', (
    tester,
  ) async {
    await open(tester);
    expect(find.text(trStrings.shadowingSentenceOf(1, 1)), findsOneWidget);
    expect(find.text('Bada kolu.'), findsOneWidget);
    expect(find.text(trStrings.shadowingListenFirst), findsOneWidget);
    await tapText(tester, trStrings.shadowingListen);
    await tapText(tester, trStrings.shadowingRecord);
    expect(find.text(trStrings.shadowingRecording), findsOneWidget);
    await tapText(tester, trStrings.shadowingStop);

    expect(
      find.text(trStrings.shadowingIssue('kolu', 'kolux')),
      findsOneWidget,
    );
    expect(find.text('A sesi kısa kalmış.'), findsOneWidget);
    expect(find.text(trStrings.shadowingHearSelf), findsOneWidget);
    await tapText(tester, trStrings.shadowingHearSelf);
    await tapText(tester, trStrings.shadowingTryAgain);
    expect(find.text(trStrings.shadowingAgainIntro), findsOneWidget);

    tutor.heard = heardAs(const []);
    await tapText(tester, trStrings.shadowingRecord);
    await tapText(tester, trStrings.shadowingStop);
    expect(find.text(trStrings.shadowingNoIssue), findsOneWidget);
    expect(find.text(trStrings.shadowingTryAgain), findsNothing);

    await tapText(tester, trStrings.shadowingFinish);
    expect(find.text(trStrings.shadowingDoneTitle), findsOneWidget);
    expect(find.text(trStrings.shadowingDoneSaid(1)), findsOneWidget);
    expect(find.text('• A sesi kısa kalmış.'), findsOneWidget);
    await tapText(tester, trStrings.cardsClose);
    expect(find.byType(ShadowingScreen), findsNothing);
  });

  testWidgets('nobody listening: the learner compares by ear', (tester) async {
    await open(tester);
    tutor.heard = null;
    await tapText(tester, trStrings.shadowingListen);
    await tapText(tester, trStrings.shadowingRecord);
    await tapText(tester, trStrings.shadowingStop);
    expect(find.text(trStrings.shadowingNotHeard), findsOneWidget);
    expect(find.text(trStrings.shadowingHearModel), findsOneWidget);
  });

  testWidgets('every view fits a small phone at double text size', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final handle = tester.ensureSemantics();
    Future<void> check() async {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    }

    await open(tester);
    await check();
    await tapText(tester, trStrings.shadowingListen);
    await tapText(tester, trStrings.shadowingRecord);
    await check();
    await tapText(tester, trStrings.shadowingStop);
    await check();
    handle.dispose();
  });
}
