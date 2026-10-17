import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/attempt_draft.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/session_repository.dart';
import 'package:dilbaz_app/features/cards/presentation/card_session_screen.dart';
import 'package:dilbaz_app/features/content/application/content_status.dart';
import 'package:dilbaz_app/features/today/application/today_controller.dart';
import 'package:dilbaz_app/features/today/presentation/today_screen.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../../helpers/pump_app.dart';

final String courseId = FakeAssessmentRepository.zzCourse.id;

/// Whether the first packs have come; the content follows it.
final _packsIn = NotifierProvider<_PacksIn, bool>(_PacksIn.new);

class _PacksIn extends Notifier<bool> {
  @override
  bool build() => false;

  void arrive() => state = true;
}

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakeTutorRepository tutor;
  late DateTime now;

  setUp(() {
    profiles = FakeProfileRepository(onboarded: true);
    tutor = FakeTutorRepository();
    now = cardNow;
  });

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    // The scroll takes effect in the next frame.
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  /// Studied [time] at [at] (by default earlier today).
  Future<void> studied(Duration time, {DateTime? at}) {
    final start = at ?? cardNow.subtract(const Duration(minutes: 40));
    return DriftSessionRepository(db).record(
      userId: FakeAuthRepository.id,
      courseId: courseId,
      deviceId: 'device-1',
      startedAt: start,
      endedAt: start.add(time),
      strands: {Strand.language: time},
    );
  }

  /// A card of [itemRef], made at [made], recalled earlier today.
  Future<void> recalled(String itemRef, {required DateTime made}) async {
    final cards = DriftCardRepository(db, now: () => made);
    final card = await cards.introduce(
      userId: FakeAuthRepository.id,
      courseId: courseId,
      itemRef: itemRef,
      mode: CardMode.speak,
    );
    await cards.recordReview(
      userId: FakeAuthRepository.id,
      courseId: courseId,
      deviceId: 'device-1',
      card: card,
      attempts: [
        AttemptDraft(
          activity: cardActivity(CardMode.speak),
          prompt: const {},
          response: const {'text': 'bada kolu', 'source': 'asr'},
          createdAtClient: cardNow.subtract(const Duration(minutes: 10)),
          verdict: 'correct',
          targetOk: true,
          latencyMs: 1500,
        ),
      ],
      rating: ReviewRating.good,
      after: SrsScheduler().review(card.memory, ReviewRating.good, at: cardNow),
    );
  }

  /// Opens the app on Today, with the card packs and what [data] adds.
  Future<void> openToday(
    WidgetTester tester, {
    Future<void> Function()? data,
  }) async {
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
      await data?.call();
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      profiles: profiles,
      db: db,
      extra: cardDataOverrides(db: db, tutor: tutor, clock: () => now),
    );
    expect(find.byType(TodayScreen), findsOneWidget);
  }

  String greeting(DateTime now) => switch (TodayGreeting.of(now)) {
    TodayGreeting.morning => trStrings.todayGreetingMorning,
    TodayGreeting.day => trStrings.todayGreetingDay,
    TodayGreeting.evening => trStrings.todayGreetingEvening,
  };

  test('the greeting follows the hour where the learner is', () {
    for (final (hour, expected) in [
      (4, TodayGreeting.evening),
      (5, TodayGreeting.morning),
      (10, TodayGreeting.morning),
      (11, TodayGreeting.day),
      (17, TodayGreeting.day),
      (18, TodayGreeting.evening),
      (23, TodayGreeting.evening),
    ]) {
      final local = DateTime(2026, 10, 1, hour, 30);
      expect(TodayGreeting.of(local.toUtc()), expected, reason: '$hour');
    }
  });

  testWidgets('Today plans once the first packs are in', (tester) async {
    // The home screen asks for the day before the packs are imported.
    profiles.silentMode = true;
    await tester.runAsync(() async => db = memoryDatabase());
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      profiles: profiles,
      db: db,
      content: (ref) => ref.watch(_packsIn)
          ? readyContent
          : const ContentStatus.unavailable(PackFailure.network),
      extra: cardDataOverrides(db: db, tutor: tutor, clock: () => now),
    );
    expect(find.text(greeting(cardNow)), findsNothing);

    await tester.runAsync(() => installCardPacks(db));
    ProviderScope.containerOf(tester.element(find.byType(TodayScreen)))
        .read(_packsIn.notifier)
        .arrive();
    await tester.pumpAndSettle();
    expect(find.text(greeting(cardNow)), findsOneWidget);
    expect(find.text(trStrings.todayCardsSummary(0, 3, 3)), findsOneWidget);
  });

  testWidgets('Today plans the cards for the time there is', (tester) async {
    profiles.silentMode = true;
    await openToday(tester);
    expect(find.text(greeting(cardNow)), findsOneWidget);
    expect(find.text(trStrings.todayTimeQuestion), findsOneWidget);
    for (final minutes in [5, 15, 30]) {
      expect(find.text(trStrings.todayMinutes(minutes)), findsOneWidget);
    }
    // Three new items: 30 s of introduction and a typed card of 25 s each.
    expect(find.text(trStrings.todayCardsSummary(0, 3, 3)), findsOneWidget);
    expect(find.text(trStrings.todayWeek(0, 5)), findsOneWidget);
    expect(find.text(trStrings.contentReady(600, 120, 588)), findsOneWidget);

    await tapText(tester, trStrings.todayCardsStart);
    expect(find.byType(CardSessionScreen), findsOneWidget);
    expect(find.text(trStrings.cardsProgress(1, 3)), findsOneWidget);
    await tapText(tester, trStrings.cardsTryType);
    await tester.enterText(find.byType(TextField), 'Bada kolu.');
    await tapText(tester, trStrings.cardsSend);
    await tapText(tester, trStrings.cardsNext);
    await tester.tap(find.byTooltip(trStrings.cardsLeave));
    await tester.pumpAndSettle();

    // Back on Today, the plan is made again.
    expect(find.byType(CardSessionScreen), findsNothing);
    expect(find.text(trStrings.todayCardsSummary(0, 2, 2)), findsOneWidget);
    expect(find.text(trStrings.todayWeek(1, 5)), findsOneWidget);
  });

  testWidgets('a short day has reviews only; the budget is the default', (
    tester,
  ) async {
    await openToday(tester);
    await tapText(tester, trStrings.todayMinutes(5));
    expect(find.text(trStrings.todayMinimumDay), findsOneWidget);
    expect(find.text(trStrings.todayCardsNone), findsOneWidget);
    expect(find.text(trStrings.todayCardsStart), findsNothing);

    await tapText(tester, trStrings.todayMinutes(15));
    expect(find.text(trStrings.todayMinimumDay), findsNothing);
    expect(find.text(trStrings.todayCardsSummary(0, 3, 3)), findsOneWidget);

    await tapText(tester, trStrings.todayMinutes(30));
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, trStrings.todayMinutes(30)),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('no choice is longer than the daily budget', (tester) async {
    profiles.dailyBudget = const Duration(minutes: 20);
    await openToday(tester);
    for (final minutes in [5, 15, 20]) {
      expect(find.text(trStrings.todayMinutes(minutes)), findsOneWidget);
    }
    expect(find.text(trStrings.todayMinutes(30)), findsNothing);
  });

  testWidgets('back after a break: a short mixed review, nothing new', (
    tester,
  ) async {
    await openToday(
      tester,
      data: () async {
        // Forty spoken cards came due while the learner was away.
        final cards = DriftCardRepository(
          db,
          now: () => cardNow.subtract(const Duration(days: 3)),
        );
        for (var i = 0; i < 40; i++) {
          await cards.introduce(
            userId: FakeAuthRepository.id,
            courseId: courseId,
            itemRef: 'zz.ws.away$i.n.1',
            mode: CardMode.speak,
          );
        }
      },
    );
    expect(find.text(trStrings.todayWelcomeBack), findsOneWidget);
    // The review cap is 10 minutes: thirty cards of 20 s.
    expect(find.text(trStrings.todayCardsSummary(30, 0, 10)), findsOneWidget);
  });

  testWidgets('the week counts the days studied since Monday', (tester) async {
    await openToday(
      tester,
      data: () async {
        // The Friday before, Tuesday twice, and today (a Thursday).
        for (final day in [
          DateTime.utc(2026, 9, 25, 9),
          DateTime.utc(2026, 9, 29, 8),
          DateTime.utc(2026, 9, 29, 10),
        ]) {
          await studied(const Duration(minutes: 20), at: day);
        }
        await studied(const Duration(minutes: 5));
      },
    );
    expect(find.text(trStrings.todayWeek(2, 5)), findsOneWidget);
    expect(find.text(trStrings.todayEnoughTitle), findsNothing);
  });

  group('"Bugünlük yeter"', () {
    testWidgets('once the time is spent: what was done, and going on', (
      tester,
    ) async {
      await openToday(
        tester,
        data: () async {
          await studied(const Duration(minutes: 30));
          await recalled(
            bada,
            made: cardNow.subtract(const Duration(hours: 1)),
          );
          await recalled(sima, made: cardNow.subtract(const Duration(days: 3)));
        },
      );
      expect(find.text(trStrings.todayEnoughTitle), findsOneWidget);
      expect(find.text(trStrings.todaySpent(30)), findsOneWidget);
      expect(find.text(trStrings.cardsDoneReviewed(1)), findsOneWidget);
      expect(find.text(trStrings.cardsDoneIntroduced(1)), findsOneWidget);
      expect(find.text(trStrings.todayTomorrowMorningCoffee), findsOneWidget);
      // No time question and no start button once the day is done.
      expect(find.text(trStrings.todayTimeQuestion), findsNothing);
      expect(find.text(trStrings.todayCardsStart), findsNothing);

      await tapText(tester, trStrings.todayGoOn);
      expect(find.byType(CardSessionScreen), findsOneWidget);
      // Only the chunk is left to learn today.
      expect(find.text(trStrings.cardsProgress(1, 1)), findsOneWidget);
    });

    for (final (anchor, text) in [
      ('lunch_break', trStrings.todayTomorrowLunchBreak),
      ('after_dinner', trStrings.todayTomorrowAfterDinner),
      ('before_bed', trStrings.todayTomorrowBeforeBed),
      (null, trStrings.todayTomorrow),
    ]) {
      testWidgets('see you tomorrow at the anchor: $anchor', (tester) async {
        profiles.anchor = anchor;
        await openToday(
          tester,
          data: () => studied(const Duration(minutes: 30)),
        );
        expect(find.text(text), findsOneWidget);
      });
    }

    testWidgets('the time chosen for today counts too', (tester) async {
      await openToday(tester, data: () => studied(const Duration(minutes: 10)));
      expect(find.text(trStrings.todayEnoughTitle), findsNothing);
      await tapText(tester, trStrings.todayMinutes(5));
      expect(find.text(trStrings.todayEnoughTitle), findsOneWidget);
      expect(find.text(trStrings.todaySpent(10)), findsOneWidget);
    });

    testWidgets('a new day plans again when the app comes back', (
      tester,
    ) async {
      await openToday(tester, data: () => studied(const Duration(minutes: 30)));
      expect(find.text(trStrings.todayEnoughTitle), findsOneWidget);

      now = cardNow.add(const Duration(days: 1));
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(trStrings.todayEnoughTitle), findsNothing);
      expect(find.text(trStrings.todayCardsSummary(0, 3, 3)), findsOneWidget);
    });

    testWidgets('cards opened from Practice wait too, unless going on', (
      tester,
    ) async {
      await openToday(tester, data: () => studied(const Duration(minutes: 30)));
      await tapText(tester, trStrings.tabPractice);
      await tapText(tester, trStrings.practiceCardsTitle);
      expect(find.text(trStrings.todayEnoughTitle), findsOneWidget);
      await tapText(tester, trStrings.todayGoOn);
      expect(find.text(trStrings.cardsProgress(1, 3)), findsOneWidget);
    });
  });

  for (final spent in [Duration.zero, const Duration(minutes: 30)]) {
    testWidgets('fits a small phone at double text size, '
        'spent ${spent.inMinutes} min', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final handle = tester.ensureSemantics();

      await openToday(tester, data: () => studied(spent));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tapText(
        tester,
        spent == Duration.zero
            ? trStrings.todayCardsStart
            : trStrings.todayGoOn,
      );
      expect(find.byType(CardSessionScreen), findsOneWidget);
      handle.dispose();
    });
  }
}
