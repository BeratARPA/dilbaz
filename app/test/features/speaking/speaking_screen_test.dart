import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/features/cards/presentation/views/hold_to_speak_button.dart';
import 'package:dilbaz_app/features/practice/presentation/practice_screen.dart';
import 'package:dilbaz_app/features/speaking/presentation/speaking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/pump_app.dart';
import 'speaking_controller_test.dart' show marks, said;

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakeTutorRepository tutor;
  late FakeSpeechRepository speech;
  late FakeAnswerRecorder recorder;

  setUp(() {
    profiles = FakeProfileRepository(onboarded: true);
    tutor = FakeTutorRepository()..annotated = marks;
    speech = FakeSpeechRepository(heard: said);
    recorder = FakeAnswerRecorder()..duration = const Duration(seconds: 75);
  });

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    // The scroll takes effect in the next frame.
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  /// Opens the speaking task from the Practice tab.
  Future<void> openSpeaking(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      profiles: profiles,
      speech: speech,
      recorder: recorder,
      db: db,
      extra: cardDataOverrides(db: db, tutor: tutor),
    );
    await tapText(tester, trStrings.tabPractice);
    await tapText(tester, trStrings.practiceSpeakingTitle);
  }

  /// Starts speaking, then stops: the recording's clock never settles.
  Future<void> record(WidgetTester tester) async {
    await tapText(tester, trStrings.speakingStart);
    await tester.ensureVisible(find.text(trStrings.speakingStop));
    await tester.pump();
    await tester.tap(find.text(trStrings.speakingStop));
    await tester.pumpAndSettle();
  }

  /// Holds the microphone while [heard] is said.
  Future<void> say(WidgetTester tester, String heard) async {
    speech.heard = heard;
    await tester.ensureVisible(find.byType(HoldToSpeakButton));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToSpeakButton)),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('Practice opens a task: speak, feedback, corrections, cards', (
    tester,
  ) async {
    await openSpeaking(tester);
    expect(find.byType(SpeakingScreen), findsOneWidget);
    expect(find.text(trStrings.speakingChooseTitle), findsOneWidget);
    expect(find.text('Şehrin'), findsOneWidget);
    expect(find.text('Evin'), findsOneWidget);
    // Anchors are for the monthly test only.
    expect(find.text('Kendini tanıt'), findsNothing);

    await tapText(tester, 'Şehrin');
    expect(find.text('Şehrin: anlat.'), findsOneWidget);
    expect(find.text('Dero ...'), findsOneWidget);
    expect(find.text('Bada demek'), findsOneWidget);
    // A2: a minute to prepare; nothing starts by itself.
    expect(find.text(trStrings.speakingPreparation(60)), findsOneWidget);

    await record(tester);
    expect(find.text(trStrings.speakingStats(0, 2, 5)), findsOneWidget);
    expect(find.text('bada doğru.'), findsOneWidget);
    expect(find.text(trStrings.speakingCorrectionNumber(1, 2)), findsOneWidget);
    expect(find.text('sima dero kolu'), findsOneWidget);
    expect(find.text('Sima dero.'), findsNothing);

    await say(tester, 'sima dero kolu');
    expect(
      find.text('${trStrings.cardsHintNumber(1)}: Bir kelime fazla.'),
      findsOneWidget,
    );
    await tapText(tester, trStrings.cardsReveal);
    expect(find.text('Sima dero.'), findsOneWidget);
    await tapText(tester, trStrings.speakingNext);

    expect(find.text(trStrings.speakingCorrectionNumber(2, 2)), findsOneWidget);
    await say(tester, 'dero kolu');
    expect(find.text(trStrings.cardsCorrect), findsOneWidget);
    await tapText(tester, trStrings.cardsNext);

    await tapText(tester, trStrings.speakingFinish);
    expect(find.text(trStrings.speakingDoneTitle), findsOneWidget);
    expect(find.text(trStrings.speakingDoneCards(2)), findsOneWidget);
    await tapText(tester, trStrings.cardsClose);
    expect(find.byType(SpeakingScreen), findsNothing);
    expect(find.byType(PracticeScreen), findsOneWidget);
  });

  testWidgets('a lost connection keeps the recording for a retry', (
    tester,
  ) async {
    speech.failure = SpeechFailure.network;
    await openSpeaking(tester);
    await tapText(tester, 'Evin');
    await record(tester);
    expect(find.text(trStrings.speakingFailedNetwork), findsOneWidget);
    speech.failure = null;
    await tapText(tester, trStrings.speakingRetry);
    expect(find.text(trStrings.speakingStrengths), findsOneWidget);
  });

  testWidgets('leaving needs no confirmation', (tester) async {
    await openSpeaking(tester);
    await tester.tap(find.byTooltip(trStrings.speakingLeave));
    await tester.pumpAndSettle();
    expect(find.byType(SpeakingScreen), findsNothing);
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

    await openSpeaking(tester);
    await check();
    await tapText(tester, 'Şehrin');
    await check();
    await record(tester);
    await check();
    await say(tester, 'sima dero kolu');
    await check();
    await tapText(tester, trStrings.cardsReveal);
    await check();
    await tapText(tester, trStrings.speakingNext);
    await say(tester, 'dero kolu');
    await tapText(tester, trStrings.cardsNext);
    await check();
    await tapText(tester, trStrings.speakingFinish);
    await check();
    handle.dispose();
  });
}
