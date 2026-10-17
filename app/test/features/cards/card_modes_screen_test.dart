import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/features/cards/presentation/views/recognize_page.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../../helpers/pump_app.dart';
import 'card_modes_test.dart' show badaHeard, moreMeanings;

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;

  setUp(() => profiles = FakeProfileRepository(onboarded: true));

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  /// Opens a card session whose first card is bada's card in [mode].
  Future<void> open(WidgetTester tester, CardMode mode) async {
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
      await badaHeard(db);
      await moreMeanings(db);
      await DriftCardRepository(
        db,
        now: () => cardNow.subtract(const Duration(days: 3)),
      ).introduce(
        userId: FakeAuthRepository.id,
        courseId: FakeAssessmentRepository.zzCourse.id,
        itemRef: bada,
        mode: mode,
      );
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      profiles: profiles,
      db: db,
      extra: cardDataOverrides(db: db, tutor: FakeTutorRepository()),
    );
    await tapText(tester, trStrings.tabPractice);
    await tapText(tester, trStrings.practiceCardsTitle);
  }

  testWidgets('listening: hear, choose, see what was heard (A03)', (
    tester,
  ) async {
    profiles.silentMode = true;
    await open(tester, CardMode.recognizeAudio);
    expect(find.byType(RecognizePage), findsOneWidget);
    expect(find.text(trStrings.cardsRecognizeListenFirst), findsOneWidget);
    // Nothing to choose before hearing.
    await tester.tap(find.text('bada demek'));
    await tester.pumpAndSettle();
    expect(find.text(trStrings.cardsNext), findsNothing);

    await tapText(tester, trStrings.cardsListen);
    await tapText(tester, 'bada demek');
    expect(find.text(trStrings.cardsRecognizeRight('bada')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tapText(tester, trStrings.cardsNext);
    expect(find.byType(RecognizePage), findsNothing);
  });

  testWidgets('cloze: the sentence with its gap and a hint (A04)', (
    tester,
  ) async {
    profiles.silentMode = true;
    await open(tester, CardMode.cloze);
    expect(find.text(trStrings.cardsClozeType), findsOneWidget);
    expect(find.text('____ kolu.'), findsOneWidget);
    expect(find.text(trStrings.cardsClozeHint('bada demek')), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'bada');
    await tapText(tester, trStrings.cardsSend);
    expect(find.text('Bada kolu.'), findsWidgets);
  });

  testWidgets('both fit a small phone at double text size', (tester) async {
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

    profiles.silentMode = true;
    await open(tester, CardMode.recognizeAudio);
    await check();
    await tapText(tester, trStrings.cardsListen);
    await tapText(tester, 'bada demek');
    await check();
    handle.dispose();
  });
}
