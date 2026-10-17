import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/features/dictation_practice/presentation/dictation_practice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../../helpers/pump_app.dart';
import 'dictation_practice_controller_test.dart' show understood;

void main() {
  late AppDatabase db;

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool known = true}) async {
    final assessments = FakeAssessmentRepository(open: false);
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
      if (known) await understood(db, assessments);
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      db: db,
      assessments: assessments,
      extra: cardDataOverrides(db: db, tutor: FakeTutorRepository()),
    );
    await tapText(tester, trStrings.tabPractice);
    await tapText(tester, trStrings.practiceDictationTitle);
  }

  testWidgets('nothing the learner can understand yet: it says why', (
    tester,
  ) async {
    await open(tester, known: false);
    expect(find.byType(DictationPracticeScreen), findsOneWidget);
    expect(find.text(trStrings.dictationNothingToHear), findsOneWidget);
  });

  testWidgets('hear, write, check: the misses by kind, then the end', (
    tester,
  ) async {
    await open(tester);
    expect(find.text(trStrings.dictationSentenceOf(1, 1)), findsOneWidget);
    // The field opens once the sentence was heard.
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tapText(tester, trStrings.dictationListen);
    await tester.enterText(find.byType(TextField), 'badan');
    await tapText(tester, trStrings.dictationCheck);

    expect(find.text(trStrings.dictationMarkEnding('bada')), findsOneWidget);
    expect(find.text(trStrings.dictationMarkMissed('kolu')), findsOneWidget);
    await tapText(tester, trStrings.dictationTryAgainSlowly);
    expect(find.text(trStrings.dictationSlowIntro), findsOneWidget);
    await tapText(tester, trStrings.dictationListen);
    await tester.enterText(find.byType(TextField), 'Bada kolu.');
    await tapText(tester, trStrings.dictationCheck);
    expect(find.text(trStrings.dictationAllHeard), findsOneWidget);

    await tapText(tester, trStrings.dictationFinish);
    expect(find.text(trStrings.dictationDoneTitle), findsOneWidget);
    expect(find.text(trStrings.dictationDoneHeard(0, 1)), findsOneWidget);
    await tapText(tester, trStrings.cardsClose);
    expect(find.byType(DictationPracticeScreen), findsNothing);
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
    await tapText(tester, trStrings.dictationListen);
    await tester.enterText(find.byType(TextField), 'bada');
    await tapText(tester, trStrings.dictationCheck);
    await check();
    handle.dispose();
  });
}
