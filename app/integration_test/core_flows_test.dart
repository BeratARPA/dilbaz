// End-to-end scenarios 1, 2, 3 and 5 of docs/15-testing.md §4. On a phone
// they run beside the real app, never in its place (docs/19-setup.md §2,
// "Uçtan uca testler"):
//
//   DILBAZ_APP_ID_SUFFIX=.local flutter test integration_test \
//     -d <device> --no-uninstall
//
// Without a phone: flutter test integration_test -d flutter-tester
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/card_content_repository.dart';
import 'package:dilbaz_app/data/sync/sync_remote.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:dilbaz_app/features/cards/presentation/views/hold_to_speak_button.dart';
import 'package:dilbaz_app/features/onboarding/presentation/onboarding_screen.dart';
import 'package:dilbaz_app/features/sync/application/sync_controller.dart';
import 'package:dilbaz_app/features/today/presentation/today_screen.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:integration_test/integration_test.dart';

import '../test/helpers/card_fixture.dart';
import '../test/helpers/placement_fixture.dart';
import '../test/helpers/pump_app.dart';
import 'support/e2e_app.dart';
import 'support/e2e_packs.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<List<AttemptRow>> attempts(AppDatabase db) => (db.select(
    db.attempts,
  )..orderBy([(t) => OrderingTerm(expression: t.createdAtClient)])).get();

  testWidgets('1: welcome, placement test, a first session of new items, '
      'then enough for today', (tester) async {
    final app = E2eApp()..bank = zzBank();
    await installFiveWords(app.db);
    await app.open(tester);

    // The welcome flow: a name, a quarter of an hour a day, a voice.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await tester.tapText(trStrings.onboardingStart);
    await tester.write('Berat', label: trStrings.onboardingNameLabel);
    await tester.tapText(trStrings.onboardingNext);
    await tester.tapText(trStrings.goalConversation);
    await tester.tapText(trStrings.onboardingNext);
    await tester.tapText(trStrings.onboardingBudgetMinutes(15));
    await tester.tapText(trStrings.onboardingNext);
    await tester.tapText(trStrings.onboardingNext);
    await tester.tapText(trStrings.onboardingNotifyLater);
    await tester.tapText(trStrings.onboardingSkip);
    await tester.tapText(trStrings.onboardingAudioConsent);
    await tester.tapText(trStrings.onboardingNext);
    await tester.tapText(trStrings.levelA1);
    await tester.tapText(trStrings.onboardingFinish);
    await tester.waitFor(find.byType(TodayScreen));
    expect(app.permissions.asked, ['microphone']);

    // The placement test, knowing nothing yet.
    await tester.tapText(trStrings.placementInviteStart);
    await tester.tapText(trStrings.placementBegin);
    await tester.tapText(trStrings.placementStartPart);
    for (var i = 0; i < 12; i++) {
      await tester.tapText(trStrings.placementWordUnknown);
    }
    await tester.tapText(trStrings.placementStartPart);
    while (await tester.waitForOneOf([
          trStrings.placementNotSure,
          trStrings.placementSkipDictation,
        ]) ==
        trStrings.placementNotSure) {
      await tester.tapText(trStrings.placementNotSure);
    }
    await tester.tapText(trStrings.placementSkipDictation);
    await tester.waitFor(find.text(trStrings.placementResultTitle('A0')));
    await tester.tapText(trStrings.placementDone);

    // The first session: four new items in a quarter of an hour, so that
    // their reviews stay under the cap (I-07). Each is shown, then asked
    // for aloud.
    await tester.tapText(trStrings.todayCardsStart);
    for (var n = 1; n <= 4; n++) {
      await tester.waitFor(find.text(trStrings.cardsProgress(n, 4)));
      await tester.tapText(trStrings.cardsTrySpeak);
      final word = wordAsked();
      // Nothing is shown before a try (I-01).
      expect(find.text(word.sentence), findsNothing);
      app
        ..now = app.now.add(const Duration(minutes: 3))
        ..speech.heard = word.sentence.toLowerCase().replaceAll('.', '');
      await tester.speak();
      await tester.waitFor(find.text(trStrings.cardsCorrect));
      expect(find.text(word.sentence), findsOneWidget);
      await tester.tapText(trStrings.cardsNext);
    }
    await tester.waitFor(find.text(trStrings.cardsDoneTitle));
    expect(find.text(trStrings.cardsDoneIntroduced(4)), findsOneWidget);
    await tester.tapText(trStrings.cardsClose);

    // Twelve minutes count, three at most a card. The three left make a
    // short day with nothing due yet.
    await tester.waitFor(find.text(trStrings.todayCardsNone));
    expect(find.text(trStrings.todayMinimumDay), findsOneWidget);
    // The learner has no more time today: enough for today.
    await tester.tapText(trStrings.todayMinutes(5));
    await tester.waitFor(find.text(trStrings.todayEnoughTitle));
    expect(find.text(trStrings.todaySpent(12)), findsOneWidget);
    expect(find.text(trStrings.cardsDoneIntroduced(4)), findsOneWidget);
    expect(find.text(trStrings.todayTomorrowMorningCoffee), findsOneWidget);
    final stored = await attempts(app.db);
    expect(stored, hasLength(4));
    expect(stored.map((a) => (a.verdict, a.response['source'])).toSet(), {
      ('correct', 'asr'),
    });
    expect(await app.db.select(app.db.cards).get(), hasLength(4));
    expect(
      (await app.db.select(app.db.assessments).get()).single.kind,
      'placement',
    );
  });

  testWidgets('2: a miss, two hints, then right: Hard, stored and queued', (
    tester,
  ) async {
    final app = E2eApp();
    await installCardPacks(app.db);
    await app.welcomed();
    app.tutor.answers.add(
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
    await app.open(tester);
    await tester.tapText(trStrings.todayCardsStart);
    await tester.tapText(trStrings.cardsTryType);

    await tester.write('Bada kolo.');
    await tester.tapText(trStrings.cardsSend);
    await tester.waitFor(find.text('Bir kelime farklı.'));
    expect(find.text(trStrings.cardsHintNumber(1)), findsOneWidget);
    expect(find.text('Bada kolu.'), findsNothing);
    await tester.tapText(trStrings.cardsHint);
    await tester.waitFor(find.text('İkinci kelimede.'));
    expect(find.text('Bada kolu.'), findsNothing);

    await tester.write('Bada kolu.');
    await tester.tapText(trStrings.cardsSend);
    await tester.waitFor(find.text(trStrings.cardsCorrect));
    await tester.tapText(trStrings.cardsNext);
    await tester.waitFor(find.text(trStrings.cardsProgress(2, 3)));

    final card = (await app.db.select(app.db.cards).get()).single;
    expect(card.itemRef, bada);
    final [miss, right] = await attempts(app.db);
    expect((miss.verdict, miss.rating), ('wrong', null));
    expect(
      (right.verdict, right.hintMaxLevel, right.rating),
      ('correct', 2, ReviewRating.hard.code),
    );
    expect(right.cardStateAfter, isNotNull);
    expect([miss.cardId, right.cardId], [card.id, card.id]);
    final queued = {
      for (final entry in await app.db.select(app.db.outbox).get())
        (entry.targetTable, entry.rowId),
    };
    expect(
      queued,
      containsAll([
        ('attempts', miss.id),
        ('attempts', right.id),
        ('cards', card.id),
      ]),
    );
  });

  testWidgets('3: what I could not say: captured, suggested, made a card, '
      'asked for the next day', (tester) async {
    final app = E2eApp();
    await installCardPacks(app.db);
    await app.welcomed();
    await app.open(tester);

    await tester.tapText(trStrings.gapCaptureButton);
    await tester.write('canım sıkıldı');
    await tester.tapText(trStrings.gapCaptureSave);
    await tester.waitFor(find.text('I am bored. We can go out.'));
    await tester.tapText(trStrings.gapEntryAddToCards);
    await tester.waitFor(find.text(trStrings.gapEntryCarded));
    final items = await app.db.select(app.db.personalItems).get();
    expect(items.map((i) => (i.kind, i.textL2)), [
      ('sentence', 'I am bored. We can go out.'),
      ('chunk', 'go out'),
    ]);
    await app.close(tester);

    // The next day, what the learner asked for comes first (docs/02 §4.3):
    // the sentence and its phrase, in either order, then the pack's three.
    app.now = app.now.add(const Duration(days: 1));
    await app.open(tester);
    await tester.tapText(trStrings.todayCardsStart);
    await tester.waitFor(find.text(trStrings.cardsProgress(1, 5)));
    final asked = await tester.waitForOneOf([for (final i in items) i.textL2]);
    await tester.tapText(trStrings.cardsTryType);
    expect(find.text(asked), findsNothing);
    await tester.write(asked);
    await tester.tapText(trStrings.cardsSend);
    await tester.waitFor(find.text(trStrings.cardsCorrect));
    await tester.tapText(trStrings.cardsNext);
    await tester.waitFor(find.text(trStrings.cardsProgress(2, 5)));

    final card = (await app.db.select(app.db.cards).get()).single;
    final item = items.singleWhere((i) => i.textL2 == asked);
    expect(card.itemRef, '$personalKeyPrefix${item.id}');
    expect((await attempts(app.db)).single.verdict, 'correct');
  });

  testWidgets('5: offline, the answer waits on the device; back online, it '
      'reaches the server', (tester) async {
    final app = E2eApp()..offline = true;
    await installCardPacks(app.db);
    await app.welcomed();
    await app.open(tester, sync: true);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TodayScreen)),
    );
    await tester.waitUntil(
      () =>
          container.read(syncControllerProvider).failure == SyncFailure.network,
    );

    await tester.tapText(trStrings.todayCardsStart);
    await tester.tapText(trStrings.cardsTryType);
    await tester.write('Bada kolu.');
    await tester.tapText(trStrings.cardsSend);
    await tester.waitFor(find.text(trStrings.cardsCorrect));
    await tester.tapText(trStrings.cardsNext);
    await tester.waitFor(find.text(trStrings.cardsProgress(2, 3)));
    await tester.tap(find.byTooltip(trStrings.cardsLeave));
    await tester.waitFor(find.byType(TodayScreen));

    final attempt = (await attempts(app.db)).single;
    final waiting = await app.db.select(app.db.outbox).get();
    expect(waiting.map((e) => e.rowId), contains(attempt.id));
    expect(app.server.table('attempts'), isEmpty);

    // The connection is back; the app syncs as it goes out of sight and
    // comes back. No frame is drawn while hidden, so it is back at once.
    app.offline = false;
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await tester.waitUntil(
      () => app.server.table('attempts').containsKey(attempt.id),
    );
    await tester.waitUntil(
      () => container.read(syncControllerProvider).failure == null,
    );
    final row = app.server.table('attempts')[attempt.id]!;
    expect(
      (row['item_ref'], row['verdict'], row['profile_id']),
      (bada, 'correct', app.userId),
    );
    expect(app.server.table('cards').keys, [attempt.cardId]);
    expect(await app.db.select(app.db.outbox).get(), isEmpty);
  });
}

extension on WidgetTester {
  /// Holds the microphone, then lets go.
  Future<void> speak() async {
    final button = find.byType(HoldToSpeakButton);
    await waitFor(button);
    final gesture = await startGesture(getCenter(button));
    await pump();
    await gesture.up();
    await pumpAndSettle();
  }
}
