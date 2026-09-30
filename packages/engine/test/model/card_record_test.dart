import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

const ReviewRating good = ReviewRating.good;
const ReviewRating hard = ReviewRating.hard;
const ReviewRating again = ReviewRating.again;

final t0 = DateTime.utc(2026, 1, 1, 8);

DateTime day(num days) => t0.add(Duration(minutes: (days * 1440).round()));

/// A card after [steps] of (day, rating, evidence) on the real scheduler.
CardRecord card(
  List<(num, ReviewRating, bool)> steps, {
  CardMode mode = CardMode.speak,
}) {
  final scheduler = SrsScheduler(SrsConfig.replay);
  var memory = scheduler.newCard(fsrsCardId: 1, now: t0);
  final reviews = <ReviewRecord>[];
  for (final (days, rating, evidence) in steps) {
    memory = scheduler.review(memory, rating, at: day(days));
    reviews.add(
      ReviewRecord(
        at: day(days),
        rating: rating,
        evidence: evidence,
        stability: memory.stability!,
      ),
    );
  }
  return CardRecord(mode: mode, memory: memory, reviews: reviews);
}

/// Two recalls on day 0, then one each on days 3, 12 and 40.
const List<(num, ReviewRating, bool)> steady = [
  (0, good, true),
  (0.007, good, true),
  (3, good, true),
  (12, good, true),
  (40, good, true),
];

void main() {
  group('CardRecord levels (docs/04-learner-model.md §3)', () {
    test('a card is learning until a recall has held for a week', () {
      final fresh = card([]);
      expect(fresh.shownStability, isNull);
      expect(fresh.level(now: t0), ItemLevel.learning);

      // Graduated to review, but with a stability under a week.
      final graduated = card(steady.sublist(0, 2));
      expect(graduated.memory.state, MemoryState.review);
      expect(graduated.shownStability, lessThan(CardRecord.recallableDays));
      expect(graduated.level(now: day(1)), ItemLevel.learning);
    });

    test('recallable: in review with a shown stability of a week', () {
      final recalled = card(steady.sublist(0, 3));
      expect(recalled.shownStability, greaterThan(CardRecord.recallableDays));
      expect(recalled.isRecallable, isTrue);
      expect(recalled.level(now: day(3)), ItemLevel.recallable);
    });

    test('forgetting drops the level at once', () {
      final lapsed = card([...steady, (70, again, false)]);
      expect(lapsed.memory.state, MemoryState.relearning);
      expect(lapsed.level(now: day(70)), ItemLevel.learning);
      // Relearned the same day: back in review, but not for a week yet.
      final relearned = card([
        ...steady,
        (70, again, false),
        (70.007, good, true),
      ]);
      expect(relearned.memory.state, MemoryState.review);
      expect(relearned.level(now: day(71)), ItemLevel.learning);
    });

    test('a month of stability alone is not durable', () {
      // Day 12 came only nine days after the review before it.
      final stable = card(steady.sublist(0, 4));
      expect(stable.shownStability, greaterThan(CardRecord.durableDays));
      expect(stable.level(now: day(12)), ItemLevel.recallable);
    });

    test(
      'durable: a first-try recall after three weeks, in the last 90 days',
      () {
        final durable = card(steady);
        expect(durable.level(now: day(40)), ItemLevel.durable);
        expect(durable.level(now: day(130)), ItemLevel.durable);
        // The spaced recall of day 40 is now older than 90 days.
        expect(durable.level(now: day(131)), ItemLevel.recallable);
      },
    );

    test('a recall with hints does not make an item durable', () {
      final aided = card([...steady.sublist(0, 4), (40, hard, true)]);
      expect(aided.shownStability, greaterThan(CardRecord.durableDays));
      expect(aided.level(now: day(40)), ItemLevel.recallable);
    });

    test('the three weeks count from the review right before', () {
      // A review without evidence on day 30 refreshed the memory; the
      // recall of day 40 bridged ten days, not four weeks.
      final refreshed = card([
        ...steady.sublist(0, 4),
        (30, hard, false),
        (40, good, true),
      ]);
      expect(refreshed.level(now: day(40)), ItemLevel.recallable);
    });

    test('reviews without evidence raise no level (I-04)', () {
      // Undecided without the LLM, or correct without the target: Hard
      // moves the schedule on, but shows nothing.
      final unshown = card([
        (0, good, true),
        (0.007, good, true),
        (3, hard, false),
        (8, hard, false),
        (20, hard, false),
      ]);
      expect(unshown.memory.state, MemoryState.review);
      expect(unshown.memory.stability, greaterThan(CardRecord.recallableDays));
      expect(unshown.shownStability, lessThan(CardRecord.recallableDays));
      expect(unshown.level(now: day(20)), ItemLevel.learning);

      final shown = card([
        (0, good, true),
        (0.007, good, true),
        (3, hard, false),
        (8, hard, false),
        (20, good, true),
      ]);
      expect(shown.level(now: day(20)), ItemLevel.recallable);
    });

    test('a first-try recall is unaided; a Hard one is not', () {
      ReviewRecord record(ReviewRating rating, {bool evidence = true}) =>
          ReviewRecord(
            at: t0,
            rating: rating,
            evidence: evidence,
            stability: 1,
          );
      expect(record(good).unaided, isTrue);
      expect(record(ReviewRating.easy).unaided, isTrue);
      expect(record(hard).unaided, isFalse);
      expect(record(again, evidence: false).unaided, isFalse);
    });
  });

  group('ItemEvidence (docs/04-learner-model.md §3)', () {
    test('an item without cards is new', () {
      const none = ItemEvidence([]);
      expect(none.productionLevel(now: t0), ItemLevel.unseen);
      expect(none.isRecognized, isFalse);
      expect(none.isKnown, isFalse);
    });

    test('the production level is that of the best production card', () {
      final item = ItemEvidence([
        card(steady.sublist(0, 2)),
        card(steady, mode: CardMode.type),
        card(steady.sublist(0, 3), mode: CardMode.cloze),
      ]);
      expect(item.productionLevel(now: day(40)), ItemLevel.durable);
      expect(item.isKnown, isTrue);
      expect(item.isRecognized, isFalse);
    });

    test('recognition is never production (I-05)', () {
      for (final mode in [CardMode.recognizeAudio, CardMode.dictation]) {
        final item = ItemEvidence([card(steady, mode: mode)]);
        expect(item.productionLevel(now: day(40)), ItemLevel.unseen);
        expect(item.isRecognized, isTrue);
        expect(item.isKnown, isTrue);
      }
    });

    test('a production card does not make an item recognized', () {
      final item = ItemEvidence([
        card(steady),
        card(steady.sublist(0, 2), mode: CardMode.recognizeAudio),
      ]);
      expect(item.isRecognized, isFalse);
      expect(item.productionLevel(now: day(40)), ItemLevel.durable);
    });

    test('levels order from new to transferred', () {
      expect(ItemLevel.values.map((l) => l.code), [
        'new',
        'learning',
        'recallable',
        'durable',
        'transferred',
      ]);
      expect(ItemLevel.durable.isAtLeast(ItemLevel.recallable), isTrue);
      expect(ItemLevel.learning.isAtLeast(ItemLevel.recallable), isFalse);
      expect(ItemLevel.recallable.isAtLeast(ItemLevel.recallable), isTrue);
    });
  });
}
