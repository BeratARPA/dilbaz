import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 26, 8);
  const cardId = 1758873600000;

  /// Ratings and review times (offsets from [t0]) covering all states.
  final plan = [
    (ReviewRating.good, Duration.zero),
    (ReviewRating.good, const Duration(minutes: 10)),
    (ReviewRating.again, const Duration(days: 3)),
    (ReviewRating.hard, const Duration(days: 3, minutes: 10)),
    (ReviewRating.good, const Duration(days: 3, minutes: 30)),
    (ReviewRating.easy, const Duration(days: 12)),
    (ReviewRating.hard, const Duration(days: 40)),
  ];

  List<CardMemory> replay(SrsScheduler scheduler) {
    var card = scheduler.newCard(fsrsCardId: cardId, now: t0);
    return [
      for (final (rating, offset) in plan)
        card = scheduler.review(card, rating, at: t0.add(offset)),
    ];
  }

  group('SrsScheduler.newCard', () {
    test('starts in learning at step 0, due now, with no memory yet', () {
      final card = SrsScheduler().newCard(fsrsCardId: cardId, now: t0);
      expect(card.fsrsCardId, cardId);
      expect(card.state, MemoryState.learning);
      expect(card.step, 0);
      expect(card.due, t0);
      expect(card.stability, isNull);
      expect(card.difficulty, isNull);
      expect(card.lastReview, isNull);
    });

    test('requires a UTC time', () {
      expect(
        () => SrsScheduler().newCard(
          fsrsCardId: cardId,
          now: DateTime(2026, 9, 26, 8),
        ),
        throwsArgumentError,
      );
    });

    test('rejects ids that are not exact web integers', () {
      final scheduler = SrsScheduler();
      for (final id in [0, -1, SrsScheduler.maxFsrsCardId + 1]) {
        expect(
          () => scheduler.newCard(fsrsCardId: id, now: t0),
          throwsArgumentError,
        );
      }
      expect(
        scheduler
            .newCard(fsrsCardId: SrsScheduler.maxFsrsCardId, now: t0)
            .fsrsCardId,
        SrsScheduler.maxFsrsCardId,
      );
    });
  });

  group('SrsScheduler.review (I-08)', () {
    test('matches package:fsrs exactly, so due dates come from FSRS', () {
      final reference = fsrs.Scheduler(enableFuzzing: false);
      var expected = fsrs.Card(cardId: cardId, due: t0);
      final actual = replay(SrsScheduler(SrsConfig.replay));
      for (final (i, (rating, offset)) in plan.indexed) {
        expected = reference
            .reviewCard(
              expected,
              fsrs.Rating.fromValue(rating.code),
              reviewDateTime: t0.add(offset),
            )
            .card;
        final card = actual[i];
        expect(card.state.code, expected.state.value, reason: 'review $i');
        expect(card.step, expected.step, reason: 'review $i');
        expect(card.stability, expected.stability, reason: 'review $i');
        expect(card.difficulty, expected.difficulty, reason: 'review $i');
        expect(card.due, expected.due, reason: 'review $i');
        expect(card.lastReview, expected.lastReview, reason: 'review $i');
      }
    });

    test('visits every memory state and keeps timestamps in UTC', () {
      final cards = replay(SrsScheduler(SrsConfig.replay));
      expect(cards.map((c) => c.state).toSet(), MemoryState.values.toSet());
      for (final card in cards) {
        expect(card.due.isUtc, isTrue);
        expect(card.lastReview!.isUtc, isTrue);
        expect(card.due.isAfter(card.lastReview!), isTrue);
      }
    });

    test('replay without fuzz is deterministic', () {
      final scheduler = SrsScheduler(SrsConfig.replay);
      expect(replay(scheduler), replay(SrsScheduler(SrsConfig.replay)));
      expect(replay(scheduler), replay(scheduler));
    });

    test('live fuzz spreads long intervals around the FSRS interval', () {
      final mature = CardMemory(
        fsrsCardId: cardId,
        state: MemoryState.review,
        due: t0.add(const Duration(days: 30)),
        stability: 30,
        difficulty: 5,
        lastReview: t0,
      );
      final at = t0.add(const Duration(days: 30));
      int intervalDays(CardMemory card) => card.due.difference(at).inDays;

      final base = intervalDays(
        SrsScheduler(SrsConfig.replay)
            .review(mature, ReviewRating.good, at: at),
      );
      final live = SrsScheduler();
      final fuzzed = {
        for (var i = 0; i < 40; i++)
          intervalDays(live.review(mature, ReviewRating.good, at: at)),
      };
      expect(fuzzed.length, greaterThan(1));
      for (final days in fuzzed) {
        expect((days - base).abs(), lessThanOrEqualTo(base * 0.25));
      }
    });

    test('requires a UTC review time', () {
      final scheduler = SrsScheduler();
      final card = scheduler.newCard(fsrsCardId: cardId, now: t0);
      expect(
        () => scheduler.review(
          card,
          ReviewRating.good,
          at: DateTime(2026, 9, 26, 9),
        ),
        throwsArgumentError,
      );
    });

    test('rejects card timestamps that are not UTC', () {
      final scheduler = SrsScheduler();
      final localDue = CardMemory(
        fsrsCardId: cardId,
        state: MemoryState.learning,
        step: 0,
        due: DateTime(2026, 9, 26, 8),
      );
      final localLastReview = CardMemory(
        fsrsCardId: cardId,
        state: MemoryState.review,
        due: t0,
        stability: 3,
        difficulty: 5,
        lastReview: DateTime(2026, 9, 23, 8),
      );
      for (final card in [localDue, localLastReview]) {
        expect(
          () => scheduler.review(card, ReviewRating.good, at: t0),
          throwsArgumentError,
        );
      }
    });
  });

  group('SrsScheduler review counts', () {
    test('count every review and each lapse from review', () {
      final cards = replay(SrsScheduler(SrsConfig.replay));
      expect(cards.map((c) => c.reps), [1, 2, 3, 4, 5, 6, 7]);
      // Only the Again on day 3 hits a graduated card.
      expect(cards.map((c) => c.lapses), [0, 0, 1, 1, 1, 1, 1]);
    });

    test('an Again while learning is not a lapse', () {
      final scheduler = SrsScheduler(SrsConfig.replay);
      final card = scheduler.review(
        scheduler.newCard(fsrsCardId: cardId, now: t0),
        ReviewRating.again,
        at: t0,
      );
      expect(card.state, MemoryState.learning);
      expect(card.reps, 1);
      expect(card.lapses, 0);
    });
  });

  group('SrsScheduler.replay', () {
    final reviews = [
      for (final (rating, offset) in plan) (rating: rating, at: t0.add(offset)),
    ];

    test('rebuilds the card from its rated reviews', () {
      final scheduler = SrsScheduler(SrsConfig.replay);
      expect(
        scheduler.replay(fsrsCardId: cardId, createdAt: t0, reviews: reviews),
        replay(scheduler).last,
      );
    });

    test('matches live memory except the fuzzed due date', () {
      // Fuzz moves due dates only; the next review reads the review times.
      final live = replay(SrsScheduler()).last;
      final rebuilt = SrsScheduler(SrsConfig.replay)
          .replay(fsrsCardId: cardId, createdAt: t0, reviews: reviews);
      expect(rebuilt.copyWith(due: live.due), live);
    });

    test('of a card without reviews is the new card', () {
      final scheduler = SrsScheduler(SrsConfig.replay);
      expect(
        scheduler.replay(fsrsCardId: cardId, createdAt: t0, reviews: []),
        scheduler.newCard(fsrsCardId: cardId, now: t0),
      );
    });

    test('needs fuzzing off', () {
      expect(
        () => SrsScheduler().replay(
          fsrsCardId: cardId,
          createdAt: t0,
          reviews: reviews,
        ),
        throwsStateError,
      );
    });

    test('rejects reviews out of order', () {
      expect(
        () => SrsScheduler(
          SrsConfig.replay,
        ).replay(fsrsCardId: cardId, createdAt: t0, reviews: reviews.reversed),
        throwsArgumentError,
      );
    });
  });

  group('SrsScheduler.retrievability', () {
    test('is 0 before the first review', () {
      final scheduler = SrsScheduler();
      final card = scheduler.newCard(fsrsCardId: cardId, now: t0);
      expect(scheduler.retrievability(card, at: t0), 0);
    });

    test('is 1 right after a review and decays over time', () {
      final scheduler = SrsScheduler(SrsConfig.replay);
      final card = replay(scheduler).last;
      final reviewed = card.lastReview!;
      expect(scheduler.retrievability(card, at: reviewed), 1);
      final later = scheduler.retrievability(
        card,
        at: reviewed.add(const Duration(days: 30)),
      );
      final muchLater = scheduler.retrievability(
        card,
        at: reviewed.add(const Duration(days: 300)),
      );
      expect(later, inExclusiveRange(0, 1));
      expect(muchLater, lessThan(later));
    });

    test('requires a UTC time', () {
      final scheduler = SrsScheduler();
      final card = scheduler.newCard(fsrsCardId: cardId, now: t0);
      expect(
        () => scheduler.retrievability(card, at: DateTime(2026, 9, 26)),
        throwsArgumentError,
      );
    });
  });

  group('SrsConfig', () {
    test('defaults to live settings with 0.90 retention', () {
      const config = SrsConfig();
      expect(config.desiredRetention, 0.90);
      expect(config.enableFuzzing, isTrue);
      expect(config.parameters, isNull);
      expect(SrsConfig.replay.enableFuzzing, isFalse);
    });

    test('rejects desired retention outside the database range', () {
      for (final retention in [0.79, 0.98]) {
        expect(
          () => SrsScheduler(SrsConfig(desiredRetention: retention)),
          throwsArgumentError,
        );
      }
      for (final retention in [
        SrsConfig.minDesiredRetention,
        SrsConfig.maxDesiredRetention,
      ]) {
        expect(
          SrsScheduler(SrsConfig(desiredRetention: retention))
              .config
              .desiredRetention,
          retention,
        );
      }
    });

    test('higher desired retention gives shorter intervals', () {
      DateTime dueWith(double retention) {
        final scheduler = SrsScheduler(
          SrsConfig(desiredRetention: retention, enableFuzzing: false),
        );
        final card = scheduler.newCard(fsrsCardId: cardId, now: t0);
        return scheduler.review(card, ReviewRating.easy, at: t0).due;
      }

      expect(dueWith(0.95).isBefore(dueWith(0.85)), isTrue);
    });

    test('reads a course: the weights of the mode group and retention', () {
      final production = [...fsrs.defaultParameters]..[2] = 9;
      final params = {'production': production, 'receptive': null};
      final config = SrsConfig.forCourse(
        group: ModeGroup.production,
        desiredRetention: 0.85,
        fsrsParams: params,
      );
      expect(config.parameters, production);
      expect(config.desiredRetention, 0.85);
      expect(config.enableFuzzing, isTrue);
      for (final other in [ModeGroup.receptive, ModeGroup.dictation]) {
        expect(
          SrsConfig.forCourse(
            group: other,
            desiredRetention: 0.9,
            fsrsParams: params,
          ).parameters,
          isNull,
        );
      }
      expect(
        SrsConfig.forCourse(
          group: ModeGroup.production,
          desiredRetention: 0.9,
        ).parameters,
        isNull,
      );
    });

    test('accepts integral weights from jsonb', () {
      final weights = <Object?>[...fsrs.defaultParameters]..[2] = 9;
      final config = SrsConfig.forCourse(
        group: ModeGroup.production,
        desiredRetention: 0.9,
        fsrsParams: {'production': weights},
      );
      expect(config.parameters![2], 9.0);
      final scheduler = SrsScheduler(config.copyWith(enableFuzzing: false));
      final card = scheduler.newCard(fsrsCardId: cardId, now: t0);
      expect(scheduler.review(card, ReviewRating.good, at: t0).stability, 9.0);
    });

    test('rejects weights that are not a list of numbers', () {
      for (final bad in <Object>[
        'weights',
        [1.0, 'x'],
        {'w': 1},
      ]) {
        expect(
          () => SrsConfig.forCourse(
            group: ModeGroup.production,
            desiredRetention: 0.9,
            fsrsParams: {'production': bad},
          ),
          throwsArgumentError,
          reason: '$bad',
        );
      }
    });

    test('uses personal FSRS parameters when given', () {
      final personal = [...fsrs.defaultParameters]..[2] = 9.0;
      final scheduler = SrsScheduler(
        SrsConfig(parameters: personal, enableFuzzing: false),
      );
      final card = scheduler.newCard(fsrsCardId: cardId, now: t0);
      final reviewed = scheduler.review(card, ReviewRating.good, at: t0);
      expect(reviewed.stability, 9.0);
    });
  });
}
