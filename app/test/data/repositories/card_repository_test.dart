import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/attempt_draft.dart';
import 'package:dilbaz_app/data/repositories/card_feedback_repository.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/data/repositories/device_repository.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pack_fixture.dart';

const userId = '0192f5a0-0000-7000-8000-000000000001';
const courseId = '0192f5a0-0000-7000-8000-0000000000c1';

void main() {
  late AppDatabase db;
  late DateTime now;
  var next = 0;

  setUp(() {
    db = memoryDatabase();
    now = DateTime.utc(2026, 10, 1, 9);
    next = 0;
  });
  tearDown(() => db.close());

  DriftCardRepository repository() =>
      DriftCardRepository(db, now: () => now, newId: () => 'id-${next++}');

  AttemptDraft draft({
    String verdict = 'correct',
    bool targetOk = true,
    int latencyMs = 1800,
    String text = 'i eat chicken every day',
    String carrier = 'en.sent.i_eat_chicken',
    Map<String, Object?>? llm,
  }) => AttemptDraft(
    activity: cardActivity(CardMode.speak),
    prompt: {'prompt_l1': 'Her gün tavuk yerim.', 'carrier': carrier},
    response: {'text': text, 'source': 'asr'},
    createdAtClient: now,
    verdict: verdict,
    targetOk: targetOk,
    latencyMs: latencyMs,
    llm: llm,
  );

  group('DeviceRepository', () {
    test('makes the device id once per profile', () async {
      final devices = DriftDeviceRepository(
        db,
        now: () => now,
        newId: () => 'device-${next++}',
        platform: () => 'android',
      );
      final first = await devices.deviceId(userId);
      expect(await devices.deviceId(userId), first);
      expect(await devices.deviceId('someone-else'), isNot(first));
      final row = (await db.select(db.devices).get()).first;
      expect(row.platform, 'android');
    });
  });

  group('CardRepository', () {
    test('introduces a new card once, queued for the server', () async {
      final cards = repository();

      final card = await cards.introduce(
        userId: userId,
        courseId: courseId,
        itemRef: 'en.ws.chicken.n.1',
        mode: CardMode.speak,
      );
      final again = await cards.introduce(
        userId: userId,
        courseId: courseId,
        itemRef: 'en.ws.chicken.n.1',
        mode: CardMode.speak,
      );

      expect(again.id, card.id);
      expect(card.memory.state, MemoryState.learning);
      expect(card.memory.due, now);
      expect(card.createdAt, now);
      expect((await cards.cards(courseId)).single.createdAt, now);
      expect(await cards.cards(courseId), hasLength(1));
      final outbox = await db.select(db.outbox).get();
      expect(outbox.map((e) => (e.targetTable, e.rowId, e.op)), [
        ('cards', card.id, 'upsert'),
      ]);
    });

    test('records a review: chained attempts, the last one rated', () async {
      final cards = repository();
      final card = await cards.introduce(
        userId: userId,
        courseId: courseId,
        itemRef: 'en.ws.chicken.n.1',
        mode: CardMode.speak,
      );
      final after = SrsScheduler().review(
        card.memory,
        ReviewRating.hard,
        at: now,
      );

      final ids = await cards.recordReview(
        userId: userId,
        courseId: courseId,
        deviceId: 'device-1',
        card: card,
        attempts: [
          draft(verdict: 'wrong', targetOk: false),
          draft(),
        ],
        rating: ReviewRating.hard,
        after: after,
      );

      final rows = await (db.select(
        db.attempts,
      )..orderBy([(t) => OrderingTerm(expression: t.id)])).get();
      expect(rows, hasLength(2));
      expect(ids, [for (final row in rows) row.id]);
      final [first, last] = rows;
      expect(first.parentAttemptId, isNull);
      expect(last.parentAttemptId, first.id);
      expect(first.rating, isNull);
      expect(first.cardStateAfter, isNull);
      expect(last.rating, ReviewRating.hard.code);
      expect(CardMemory.fromJson(last.cardStateAfter!), after);
      expect(last.deviceId, 'device-1');
      expect(last.pendingPush, isTrue);

      final stored = (await cards.cards(courseId)).single;
      expect(stored.memory, after);
      final outbox = await db.select(db.outbox).get();
      expect(outbox.skip(1).map((e) => (e.targetTable, e.op)), [
        ('attempts', 'insert'),
        ('attempts', 'insert'),
        ('cards', 'upsert'),
      ]);
    });

    test('a review needs at least one attempt', () async {
      final cards = repository();
      final card = await cards.introduce(
        userId: userId,
        courseId: courseId,
        itemRef: 'en.ws.chicken.n.1',
        mode: CardMode.speak,
      );
      expect(
        () => cards.recordReview(
          userId: userId,
          courseId: courseId,
          deviceId: 'device-1',
          card: card,
          attempts: const [],
          rating: ReviewRating.good,
          after: card.memory,
        ),
        throwsArgumentError,
      );
    });

    test('item levels are projected from the rated attempts (I-04)', () async {
      final cards = repository();
      final scheduler = SrsScheduler();
      final recalled = await cards.introduce(
        userId: userId,
        courseId: courseId,
        itemRef: 'en.ws.chicken.n.1',
        mode: CardMode.speak,
      );
      final missed = await cards.introduce(
        userId: userId,
        courseId: courseId,
        itemRef: 'en.ws.milk.n.1',
        mode: CardMode.speak,
      );
      // Recalled on the first try, twice, weeks apart.
      var memory = recalled.memory;
      for (final at in [now, now.add(const Duration(days: 20))]) {
        memory = scheduler.review(memory, ReviewRating.good, at: at);
        now = at;
        await cards.recordReview(
          userId: userId,
          courseId: courseId,
          deviceId: 'device-1',
          card: (
            id: recalled.id,
            itemRef: recalled.itemRef,
            mode: recalled.mode,
            memory: memory,
            createdAt: recalled.createdAt,
          ),
          attempts: [draft()],
          rating: ReviewRating.good,
          after: memory,
        );
      }
      final forgotten = scheduler.review(
        missed.memory,
        ReviewRating.again,
        at: now,
      );
      await cards.recordReview(
        userId: userId,
        courseId: courseId,
        deviceId: 'device-1',
        card: missed,
        attempts: [draft(verdict: 'wrong', targetOk: false)],
        rating: ReviewRating.again,
        after: forgotten,
      );

      final evidence = await cards.evidence(courseId);
      ItemLevel level(String key) =>
          evidence[key]?.productionLevel(now: now) ?? ItemLevel.unseen;

      expect(level('en.ws.chicken.n.1'), ItemLevel.recallable);
      expect(level('en.ws.milk.n.1'), ItemLevel.learning);
      expect(level('en.ws.tea.n.1'), ItemLevel.unseen);
    });

    test('recent latencies are the newest answers of the mode', () async {
      final cards = repository();
      final card = await cards.introduce(
        userId: userId,
        courseId: courseId,
        itemRef: 'en.ws.chicken.n.1',
        mode: CardMode.speak,
      );
      for (final ms in [900, 1200, 1500]) {
        now = now.add(const Duration(minutes: 1));
        await cards.recordReview(
          userId: userId,
          courseId: courseId,
          deviceId: 'device-1',
          card: card,
          attempts: [draft(latencyMs: ms)],
          rating: ReviewRating.good,
          after: card.memory,
        );
      }
      expect(await cards.recentLatencies(courseId, CardMode.speak), [
        1500,
        1200,
        900,
      ]);
      expect(await cards.recentLatencies(courseId, CardMode.type), isEmpty);
    });

    test('first-try recalls since a moment: their share and count', () async {
      final cards = repository();
      final card = await cards.introduce(
        userId: userId,
        courseId: courseId,
        itemRef: 'en.ws.chicken.n.1',
        mode: CardMode.speak,
      );
      Future<void> review(ReviewRating rating, {bool missFirst = false}) =>
          cards.recordReview(
            userId: userId,
            courseId: courseId,
            deviceId: 'device-1',
            card: card,
            attempts: [
              if (missFirst) draft(verdict: 'wrong', targetOk: false),
              draft(),
            ],
            rating: rating,
            after: card.memory,
          );

      await review(ReviewRating.again);
      final since = now.add(const Duration(days: 1));
      now = now.add(const Duration(days: 2));
      await review(ReviewRating.good);
      await review(ReviewRating.hard, missFirst: true);
      await review(ReviewRating.easy);
      await review(ReviewRating.again, missFirst: true);

      // Only the rated attempt of a review counts.
      expect(await cards.reviewsSince(courseId, since), 4);
      expect(await cards.unaidedAccuracySince(courseId, since), 0.5);
      final later = now.add(const Duration(minutes: 1));
      expect(await cards.reviewsSince(courseId, later), 0);
      expect(await cards.unaidedAccuracySince(courseId, later), isNull);
      expect(await cards.reviewsSince('another-course', since), 0);
    });

    test(
      "the LLM's accepted answers to a carrier are the learner's own",
      () async {
        final cards = repository();
        final card = await cards.introduce(
          userId: userId,
          courseId: courseId,
          itemRef: 'en.ws.chicken.n.1',
          mode: CardMode.speak,
        );
        const judged = {'route': 'answer_check', 'provider': 'groq'};
        await cards.recordReview(
          userId: userId,
          courseId: courseId,
          deviceId: 'device-1',
          card: card,
          attempts: [
            draft(
              verdict: 'acceptable_variant',
              targetOk: false,
              text: 'I have chicken daily',
              llm: judged,
            ),
            draft(
              verdict: 'acceptable_variant',
              text: 'Every day I eat chicken',
              llm: judged,
            ),
            // Listed answers match without the LLM.
            draft(verdict: 'acceptable_variant', text: 'I eat chicken daily'),
            // Another carrier, another prompt.
            draft(
              verdict: 'acceptable_variant',
              text: 'Chicken is my food',
              carrier: 'en.sent.other',
              llm: judged,
            ),
            draft(verdict: 'wrong', targetOk: false, text: 'I eat chickens'),
          ],
          rating: ReviewRating.hard,
          after: card.memory,
        );

        final own = await cards.personalAnswers(
          courseId: courseId,
          itemRef: 'en.ws.chicken.n.1',
          carrierKey: 'en.sent.i_eat_chicken',
        );
        expect(own.variants, ['Every day I eat chicken']);
        expect(own.alternatives, ['I have chicken daily']);
        final none = await cards.personalAnswers(
          courseId: courseId,
          itemRef: 'en.ws.milk.n.1',
          carrierKey: 'en.sent.i_eat_chicken',
        );
        expect([...none.variants, ...none.alternatives], isEmpty);
      },
    );

    group('after the review', () {
      late DriftCardRepository cards;
      late DriftCardFeedbackRepository feedback;
      late StoredCard card;

      setUp(() async {
        cards = repository();
        feedback = DriftCardFeedbackRepository(db, now: () => now);
        card = await cards.introduce(
          userId: userId,
          courseId: courseId,
          itemRef: 'en.ws.chicken.n.1',
          mode: CardMode.speak,
        );
      });

      /// An answer checked without the LLM: Hard, no evidence.
      Future<String> undecided({String text = 'i eat chiken'}) async {
        final after = SrsScheduler().review(
          card.memory,
          ReviewRating.hard,
          at: now,
        );
        final ids = await cards.recordReview(
          userId: userId,
          courseId: courseId,
          deviceId: 'device-1',
          card: card,
          attempts: [draft(verdict: 'uncertain', targetOk: false, text: text)],
          rating: ReviewRating.hard,
          after: after,
        );
        return ids.single;
      }

      Future<bool> evidence() async => (await cards.evidence(
        courseId,
      ))['en.ws.chicken.n.1']!.cards.single.reviews.single.evidence;

      test("the tutor's late verdict corrects the evidence, not the "
          'rating', () async {
        final id = await undecided();
        expect(await evidence(), isFalse);

        await feedback.resolve(
          userId: userId,
          attemptId: id,
          verdict: const {'verdict': 'minor_error', 'target_ok': true},
        );

        expect(await evidence(), isTrue);
        final attempt = await db.select(db.attempts).getSingle();
        expect(attempt.rating, ReviewRating.hard.code);
        expect(attempt.verdict, 'uncertain');
      });

      test('a late verdict that cannot say changes nothing', () async {
        final id = await undecided();
        await feedback.resolve(
          userId: userId,
          attemptId: id,
          verdict: const {'code': 'refused'},
        );
        expect(await evidence(), isFalse);
      });

      test("an answer the tutor accepts late is the learner's own", () async {
        final id = await undecided(text: 'I have chicken every day');
        await feedback.resolve(
          userId: userId,
          attemptId: id,
          verdict: const {'verdict': 'acceptable_variant', 'target_ok': false},
        );
        final own = await cards.personalAnswers(
          courseId: courseId,
          itemRef: 'en.ws.chicken.n.1',
          carrierKey: 'en.sent.i_eat_chicken',
        );
        expect(own.alternatives, ['I have chicken every day']);
        expect(own.variants, isEmpty);
      });

      test('attempts of a card merged on sync count for the card it became '
          '(docs/12 §6)', () async {
        final after = SrsScheduler().review(
          card.memory,
          ReviewRating.good,
          at: now,
        );
        await cards.recordReview(
          userId: userId,
          courseId: courseId,
          deviceId: 'device-1',
          card: card,
          attempts: [draft()],
          rating: ReviewRating.good,
          after: after,
        );
        // The sync replaced the card with the server's card of the item.
        await (db.update(db.cards)..where((t) => t.id.equals(card.id))).write(
          const CardsCompanion(id: Value('server-card')),
        );

        final reviews = (await cards.evidence(
          courseId,
        ))['en.ws.chicken.n.1']!.cards.single.reviews;
        expect(reviews, hasLength(1));
        expect(reviews.single.evidence, isTrue);
      });
    });
  });
}
