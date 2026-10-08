import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/cards/presentation/card_session_screen.dart';
import 'package:dilbaz_app/features/cards/presentation/views/hold_to_speak_button.dart';
import 'package:dilbaz_app/features/practice/presentation/practice_screen.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../../helpers/pump_app.dart';

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakeTutorRepository tutor;
  late FakeSpeechRepository speech;
  late FakeClipPlayer player;

  setUp(() {
    profiles = FakeProfileRepository(onboarded: true);
    tutor = FakeTutorRepository();
    speech = FakeSpeechRepository(heard: 'bada kolu');
    player = FakeClipPlayer();
  });

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    // The scroll takes effect in the next frame.
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  /// Opens a card session from the Practice tab.
  Future<void> openCards(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      profiles: profiles,
      speech: speech,
      player: player,
      extra: cardDataOverrides(db: db, tutor: tutor),
    );
    await tapText(tester, trStrings.tabPractice);
    await tapText(tester, trStrings.practiceCardsTitle);
  }

  /// Holds the microphone, then lets go.
  Future<void> speak(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToSpeakButton)),
    );
    await tester.pump();
    expect(find.text(trStrings.cardsRecording), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String answer) async {
    await tester.enterText(find.byType(TextField), answer);
    await tapText(tester, trStrings.cardsSend);
  }

  testWidgets('Practice opens the cards: a new item, then its card', (
    tester,
  ) async {
    await openCards(tester);
    expect(find.byType(CardSessionScreen), findsOneWidget);
    expect(find.text(trStrings.cardsProgress(1, 3)), findsOneWidget);
    expect(find.text('bada'), findsOneWidget);
    expect(find.text('bada demek'), findsOneWidget);
    expect(find.text('Bada kolu.'), findsOneWidget);
    // The sentence plays once by itself.
    expect(player.played, hasLength(1));

    await tapText(tester, trStrings.cardsTrySpeak);
    expect(find.text('Bada kolu diye sor.'), findsOneWidget);
    expect(find.text('dosta'), findsOneWidget);
    // Nothing is shown before a try (I-01).
    expect(find.text('Bada kolu.'), findsNothing);
    expect(find.text(trStrings.cardsReveal), findsNothing);

    await speak(tester);
    expect(find.text(trStrings.cardsCorrect), findsOneWidget);
    expect(find.text('Bada kolu.'), findsOneWidget);
    expect(find.text(trStrings.cardsSayOnce), findsOneWidget);

    await tapText(tester, trStrings.cardsNext);
    expect(find.text(trStrings.cardsProgress(2, 3)), findsOneWidget);
    expect(find.text('sima'), findsOneWidget);
  });

  testWidgets('a miss shows a hint; the answer opens on request', (
    tester,
  ) async {
    tutor.failure = TutorFailure.network;
    await openCards(tester);
    await tapText(tester, trStrings.cardsTrySpeak);
    await tapText(tester, trStrings.cardsTypeInstead);
    await type(tester, 'Kolu.');

    expect(find.text(trStrings.cardsTryAgain), findsOneWidget);
    expect(find.text(trStrings.cardsHintNumber(1)), findsOneWidget);
    expect(find.text(trStrings.hintMissingWord), findsOneWidget);
    expect(find.text(trStrings.cardsOfflineNetwork), findsOneWidget);

    await tapText(tester, trStrings.cardsHint);
    expect(find.text(trStrings.hintPlaceBefore('kolu')), findsOneWidget);

    await tapText(tester, trStrings.cardsReveal);
    expect(find.text(trStrings.cardsTheSentence), findsOneWidget);
    expect(find.text('Bada kolu.'), findsOneWidget);
  });

  testWidgets('"yanlış duyuldu" types over what was heard', (tester) async {
    speech.heard = 'bada kulu';
    tutor.answers.add(
      llmCheck(
        Verdict.wrong,
        ladder: const LlmLadder(
          h1: 'Bir kelime farklı.',
          h2: '',
          h3: '',
          h4: 'Bada kolu.',
        ),
      ),
    );
    await openCards(tester);
    await tapText(tester, trStrings.cardsTrySpeak);
    await speak(tester);
    expect(find.text(trStrings.cardsHeard), findsOneWidget);
    expect(find.text('bada kulu'), findsOneWidget);
    expect(find.text('Bir kelime farklı.'), findsOneWidget);

    await tapText(tester, trStrings.cardsMisheard);
    await tester.enterText(find.byType(TextField), 'Bada kolu.');
    await tapText(tester, trStrings.cardsFixSave);
    expect(find.text(trStrings.cardsCorrect), findsOneWidget);
  });

  testWidgets('"did you mean" waits for a yes', (tester) async {
    await openCards(tester);
    await tapText(tester, trStrings.cardsTrySpeak);
    await tapText(tester, trStrings.cardsTypeInstead);
    await type(tester, 'Bada kolum.');
    expect(find.text(trStrings.cardsDidYouMean), findsOneWidget);
    await tapText(tester, trStrings.cardsDidYouMeanYes);
    expect(find.text(trStrings.cardsCorrect), findsOneWidget);
  });

  testWidgets('in silent mode the session is typed and ends with a summary', (
    tester,
  ) async {
    profiles.silentMode = true;
    await openCards(tester);
    // Nothing plays by itself in silent mode.
    expect(player.played, isEmpty);
    for (final answer in ['Bada kolu.', 'Sima dero.', 'Dero kolu.']) {
      await tapText(tester, trStrings.cardsTryType);
      expect(find.byType(HoldToSpeakButton), findsNothing);
      await type(tester, answer);
      await tapText(tester, trStrings.cardsNext);
    }
    expect(find.text(trStrings.cardsDoneTitle), findsOneWidget);
    expect(find.text(trStrings.cardsDoneIntroduced(3)), findsOneWidget);
    await tapText(tester, trStrings.cardsClose);
    expect(find.byType(PracticeScreen), findsOneWidget);
    expect(find.byType(CardSessionScreen), findsNothing);
  });

  testWidgets('leaving needs no confirmation', (tester) async {
    await openCards(tester);
    await tester.tap(find.byTooltip(trStrings.cardsLeave));
    await tester.pumpAndSettle();
    expect(find.byType(CardSessionScreen), findsNothing);
    expect(find.byType(PracticeScreen), findsOneWidget);
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

    tutor.answers.add(
      llmCheck(
        Verdict.wrong,
        ladder: const LlmLadder(
          h1: 'Bir kelime farklı.',
          h2: 'İkinci kelimede.',
          h3: '',
          h4: 'Bada kolu.',
        ),
      ),
    );
    await openCards(tester);
    await check();
    await tapText(tester, trStrings.cardsTrySpeak);
    await check();
    await tapText(tester, trStrings.cardsTypeInstead);
    await type(tester, 'Bada kolo.');
    await check();
    await type(tester, 'Bada kolum.');
    expect(find.text(trStrings.cardsDidYouMean), findsOneWidget);
    await check();
    await tapText(tester, trStrings.cardsDidYouMeanYes);
    await check();
    await tapText(tester, trStrings.cardsNext);
    await tapText(tester, trStrings.cardsTrySpeak);
    await tapText(tester, trStrings.cardsTypeInstead);
    await type(tester, 'Sima dero.');
    await tapText(tester, trStrings.cardsNext);
    await tapText(tester, trStrings.cardsTrySpeak);
    await tapText(tester, trStrings.cardsTypeInstead);
    await type(tester, 'Dero kolu.');
    await tapText(tester, trStrings.cardsNext);
    expect(find.text(trStrings.cardsDoneTitle), findsOneWidget);
    await check();
    handle.dispose();
  });
}
