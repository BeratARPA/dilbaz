import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/features/placement/presentation/placement_screen.dart';
import 'package:dilbaz_app/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/placement_fixture.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    // The scroll takes effect in the next frame.
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<FakeAssessmentRepository> openTest(
    WidgetTester tester, {
    FakeClipPlayer? player,
    FakePackAudio? audio,
  }) async {
    final assessments = FakeAssessmentRepository();
    await tester.pumpDilbazApp(
      assessments: assessments,
      placements: FakeBankRepository(zzBank()),
      player: player,
      audio: audio,
    );
    await tapText(tester, trStrings.placementInviteStart);
    return assessments;
  }

  /// Answers every word, knowing none.
  Future<void> answerWords(WidgetTester tester) async {
    await tapText(tester, trStrings.placementBegin);
    await tapText(tester, trStrings.placementStartPart);
    for (var i = 0; i < 12; i++) {
      await tapText(tester, trStrings.placementWordUnknown);
    }
  }

  group('placement invitation on Today', () {
    testWidgets('is there while the course has no placement test', (
      tester,
    ) async {
      await tester.pumpDilbazApp(
        assessments: FakeAssessmentRepository(),
        placements: FakeBankRepository(zzBank()),
      );

      expect(find.text(trStrings.placementInviteTitle), findsOneWidget);
      expect(find.text(trStrings.placementInviteBody), findsOneWidget);
    });

    testWidgets('is not there without a test on the device', (tester) async {
      await tester.pumpDilbazApp(
        assessments: FakeAssessmentRepository(),
        placements: FakeBankRepository(null),
      );

      expect(find.text(trStrings.placementInviteTitle), findsNothing);
    });

    testWidgets('can be put aside without a word more', (tester) async {
      await tester.pumpDilbazApp(
        assessments: FakeAssessmentRepository(),
        placements: FakeBankRepository(zzBank()),
      );

      await tapText(tester, trStrings.placementInviteLater);

      expect(find.text(trStrings.placementInviteTitle), findsNothing);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('opens the test over the tabs', (tester) async {
      await openTest(tester);

      expect(find.byType(PlacementScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text(trStrings.placementOverviewBody), findsOneWidget);
      expect(find.text(trStrings.placementPartWords), findsOneWidget);
      expect(find.text(trStrings.placementPartDictation), findsOneWidget);
    });
  });

  group('PlacementScreen', () {
    testWidgets('a whole test ends with what it found', (tester) async {
      final player = FakeClipPlayer();
      final assessments = await openTest(tester, player: player);
      await answerWords(tester);

      expect(find.text(trStrings.placementGrammarIntro), findsOneWidget);
      await tapText(tester, trStrings.placementStartPart);
      expect(find.text(trStrings.placementQuestionNumber(1)), findsOneWidget);
      // Nothing is marked right or wrong on the way.
      var questions = 0;
      while (find.text(trStrings.placementNotSure).evaluate().isNotEmpty) {
        await tapText(tester, trStrings.placementNotSure);
        questions++;
      }
      expect(questions, inInclusiveRange(12, 15));

      expect(find.text(trStrings.placementDictationIntro), findsOneWidget);
      await tapText(tester, trStrings.placementStartPart);
      expect(find.text(trStrings.placementSentenceOf(1, 2)), findsOneWidget);
      // The field opens once the sentence was heard.
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tapText(tester, trStrings.placementListen);
      expect(player.played, ['/clips/zz/1/v1/one.mp3']);
      expect(find.text(trStrings.placementPlaysLeft(1)), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Bada kolu.');
      await tapText(tester, trStrings.placementContinue);

      expect(find.text(trStrings.placementSentenceOf(2, 2)), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tapText(tester, trStrings.placementListen);
      await tapText(tester, trStrings.placementListenAgain);
      expect(find.text(trStrings.placementPlaysLeft(0)), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'kolu bada kolu');
      await tapText(tester, trStrings.placementContinue);

      // No word known, no grammar choice made: the bottom of each scale.
      expect(find.text(trStrings.placementResultTitle('A0')), findsOneWidget);
      expect(
        find.text(trStrings.placementSkillVocabulary('A0')),
        findsOneWidget,
      );
      expect(find.text(trStrings.placementSkillGrammar('A0')), findsOneWidget);
      expect(
        find.text(
          trStrings.placementSkillListening(trStrings.levelAndAbove('A2')),
        ),
        findsOneWidget,
      );
      expect(find.text(trStrings.placementResultVocabulary(0)), findsOneWidget);
      expect(assessments.saved, hasLength(1));
      // The optional first recording (docs/06 §2 part 4).
      expect(find.text(trStrings.placementBaselineOffer), findsOneWidget);

      await tapText(tester, trStrings.placementDone);
      expect(find.byType(TodayScreen), findsOneWidget);
      // The test is taken: no invitation any more.
      expect(find.text(trStrings.placementInviteTitle), findsNothing);
    });

    testWidgets('leaving asks first and keeps nothing half-done', (
      tester,
    ) async {
      final assessments = await openTest(tester);
      await tapText(tester, trStrings.placementBegin);
      await tapText(tester, trStrings.placementStartPart);
      await tapText(tester, trStrings.placementWordKnown);

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text(trStrings.placementLeaveBody), findsOneWidget);
      await tapText(tester, trStrings.placementLeaveCancel);
      expect(find.text(trStrings.placementProgress(2, 12)), findsOneWidget);

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      await tapText(tester, trStrings.placementLeaveConfirm);

      expect(find.byType(PlacementScreen), findsNothing);
      expect(assessments.saved, isEmpty);
    });

    testWidgets('the system back button asks before leaving too', (
      tester,
    ) async {
      await openTest(tester);
      await tapText(tester, trStrings.placementBegin);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(trStrings.placementLeaveTitle), findsOneWidget);
    });

    testWidgets('the dictation can be left out', (tester) async {
      final assessments = await openTest(tester);
      await answerWords(tester);
      await tapText(tester, trStrings.placementStartPart);
      while (find.text(trStrings.placementNotSure).evaluate().isNotEmpty) {
        await tapText(tester, trStrings.placementNotSure);
      }

      await tapText(tester, trStrings.placementSkipDictation);

      expect(find.text(trStrings.placementResultTitle('A0')), findsOneWidget);
      expect(
        find.textContaining(trStrings.placementSkillListening('')),
        findsNothing,
      );
      expect(assessments.saved.single.skills, hasLength(2));
    });

    testWidgets('a clip that cannot be had is reported calmly', (tester) async {
      final audio = FakePackAudio();
      await openTest(tester, audio: audio);
      await answerWords(tester);
      await tapText(tester, trStrings.placementStartPart);
      while (find.text(trStrings.placementNotSure).evaluate().isNotEmpty) {
        await tapText(tester, trStrings.placementNotSure);
      }
      await tapText(tester, trStrings.placementStartPart);

      audio.failure = PackFailure.network;
      await tapText(tester, trStrings.placementListen);

      expect(find.text(trStrings.placementAudioFailure), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.text(trStrings.placementSkipDictation), findsOneWidget);
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

      await openTest(tester);
      Future<void> check() async {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }

      await check();
      await tapText(tester, trStrings.placementBegin);
      await check();
      await tapText(tester, trStrings.placementStartPart);
      await check();
      for (var i = 0; i < 12; i++) {
        await tapText(tester, trStrings.placementWordKnown);
      }
      await tapText(tester, trStrings.placementStartPart);
      await check();
      while (find.text(trStrings.placementNotSure).evaluate().isNotEmpty) {
        await tapText(tester, trStrings.placementNotSure);
      }
      await check();
      await tapText(tester, trStrings.placementStartPart);
      await tapText(tester, trStrings.placementListen);
      await check();
      await tester.enterText(find.byType(TextField), 'bada');
      await tapText(tester, trStrings.placementContinue);
      await tapText(tester, trStrings.placementListen);
      await tapText(tester, trStrings.placementContinue);
      await check();
      handle.dispose();
    });
  });
}
