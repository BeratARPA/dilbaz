import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/features/fluency/presentation/fluency_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/pump_app.dart';
import '../speaking/speaking_controller_test.dart' show said;
import 'fluency_controller_test.dart' show spokeAbout;

void main() {
  late AppDatabase db;

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  /// Opens 4/3/2 from the Practice tab; [spoken] puts a task spoken about
  /// on the device first.
  Future<void> open(WidgetTester tester, {bool spoken = true}) async {
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
      if (spoken) await spokeAbout(db, cityTask);
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      profiles: FakeProfileRepository(onboarded: true),
      speech: FakeSpeechRepository(heard: said),
      recorder: FakeAnswerRecorder()..duration = const Duration(seconds: 50),
      db: db,
      extra: cardDataOverrides(db: db, tutor: FakeTutorRepository()),
    );
    await tapText(tester, trStrings.tabPractice);
    await tapText(tester, trStrings.practiceFluencyTitle);
  }

  /// Starts the round, then stops it: its clock never settles.
  Future<void> round(WidgetTester tester) async {
    await tapText(tester, trStrings.speakingStart);
    await tester.ensureVisible(find.text(trStrings.speakingStop));
    await tester.pump();
    await tester.tap(find.text(trStrings.speakingStop));
    await tester.pumpAndSettle();
  }

  testWidgets('without a topic spoken about, it says how to get one', (
    tester,
  ) async {
    await open(tester, spoken: false);
    expect(find.byType(FluencyScreen), findsOneWidget);
    expect(find.text(trStrings.fluencyNoTopic), findsOneWidget);
  });

  testWidgets('a topic, three rounds, their measures, the bars', (
    tester,
  ) async {
    await open(tester);
    expect(
      find.text(
        trStrings.fluencyRoundsNote(
          trStrings.fluencyMinutes('2'),
          trStrings.fluencyMinutes('1,5'),
          trStrings.fluencyMinutes('1'),
        ),
      ),
      findsOneWidget,
    );
    await tapText(tester, 'Şehrin');
    expect(find.text(trStrings.fluencyRoundNumber(1)), findsOneWidget);
    expect(find.text(trStrings.speakingInEnglish), findsOneWidget);

    await round(tester);
    expect(find.text(trStrings.fluencyRoundResult(1)), findsOneWidget);
    expect(
      find.text(trStrings.fluencyNext(trStrings.fluencyMinutes('1,5'))),
      findsOneWidget,
    );
    await tapText(tester, trStrings.fluencyNextRound);
    expect(find.text(trStrings.fluencyRoundNumber(2)), findsOneWidget);
    await round(tester);
    await tapText(tester, trStrings.fluencyNextRound);
    await round(tester);

    expect(find.text(trStrings.fluencyDoneTitle), findsOneWidget);
    // Three rows, and three bars with the same labels.
    expect(find.text(trStrings.fluencyRoundResult(3)), findsNWidgets(2));
    await tapText(tester, trStrings.cardsClose);
    expect(find.byType(FluencyScreen), findsNothing);
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
    await tapText(tester, 'Şehrin');
    await check();
    await round(tester);
    await check();
    handle.dispose();
  });
}
