import 'dart:math';

import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

import '../fixtures/zz/zz_pack.dart';

final now = DateTime.utc(2026, 6, 15, 8);
final zz = ZzPack.generate();
final List<ContentItem> senses = zz.ofKind(ItemKind.wordSense);
const PlannerConfig config = PlannerConfig();
final planner = Planner();

Duration minutes(num value) => Duration(seconds: (value * 60).round());

Duration reviewTime(Iterable<PlanCard> cards) => cards.fold(
  Duration.zero,
  (total, card) => total + config.cardDuration[card.mode]!,
);

/// A card last reviewed [daysAgo] days ago after [ratings], oldest first.
PlanCard card(
  int number, {
  List<ReviewRating> ratings = const [ReviewRating.good, ReviewRating.good],
  num daysAgo = 10,
  CardMode mode = CardMode.speak,
  bool focus = false,
  String? itemKey,
}) {
  final scheduler = SrsScheduler(SrsConfig.replay);
  final at = now.subtract(minutes(daysAgo * 1440));
  var memory = scheduler.newCard(fsrsCardId: number + 1, now: at);
  for (final rating in ratings) {
    memory = scheduler.review(memory, rating, at: at);
  }
  return PlanCard(
    id: 'card-${number.toString().padLeft(4, '0')}',
    itemKey: itemKey ?? senses[number % senses.length].key,
    mode: mode,
    memory: memory,
    focus: focus,
  );
}

/// A random learner and what the planner is given for them.
final class World {
  new(Random random, {int idleDays = 0}) {
    final scheduler = SrsScheduler(SrsConfig.replay);
    final idle = Duration(days: idleDays);
    cards = [
      for (var i = 0; i < random.nextInt(250); i++)
        () {
          var at = now.subtract(idle + minutes(random.nextInt(120 * 1440) + 1));
          var memory = scheduler.newCard(fsrsCardId: i + 1, now: at);
          for (var review = 0; review <= random.nextInt(6); review++) {
            final rating = ReviewRating.values[random.nextInt(4)];
            memory = scheduler.review(memory, rating, at: at);
            final next = memory.due.add(minutes(random.nextInt(3 * 1440)));
            if (next.isAfter(now.subtract(idle))) break;
            at = next;
          }
          return PlanCard(
            id: 'card-${i.toString().padLeft(4, '0')}',
            itemKey: senses[i % senses.length].key,
            mode: CardMode.values[random.nextInt(CardMode.values.length)],
            memory: memory,
            focus: random.nextInt(10) == 0,
          );
        }(),
    ];
    final daily = minutes([10, 15, 20, 30, 45, 60][random.nextInt(6)]);
    final snapshot = LearnerSnapshot(
      level: CefrLevel.values[random.nextInt(4)],
      dailyBudget: daily,
      spentToday: minutes(random.nextInt(daily.inMinutes + 5)),
      recentUnaidedAccuracy: random.nextBool()
          ? null
          : 0.4 + random.nextDouble() * 0.6,
      weekStrandTime: {
        for (final strand in Strand.values) strand: minutes(random.nextInt(60)),
      },
      silentMode: random.nextInt(4) == 0,
    );
    available = [
      null,
      null,
      minutes(5),
      minutes(15),
      minutes(30),
    ][random.nextInt(5)];
    newCandidates = [for (final sense in senses) sense.key]..shuffle(random);
    options = [
      for (var i = 0; i < random.nextInt(9); i++)
        PlanOption(
          activity: 'activity_${random.nextInt(5)}',
          ref: 'ref_$i',
          strand: Strand.values[random.nextInt(4)],
          duration: minutes(3 + random.nextInt(10)),
          supportsUnprovenCanDo: random.nextBool(),
          focus: random.nextBool(),
          fresh: random.nextBool(),
          together: random.nextInt(4) == 0,
        ),
    ];
    partnerAvailable = random.nextBool();
    seed = random.nextInt(1 << 31);
    // From the world's own seed, so that the shared stream stays as it was.
    learner = snapshot.copyWith(newToday: seed % 8);
  }

  late final List<PlanCard> cards;
  late final LearnerSnapshot learner;
  late final Duration? available;
  late final List<String> newCandidates;
  late final List<PlanOption> options;
  late final bool partnerAvailable;
  late final int seed;

  TodayPlan plan({int? seed, List<PlanCard>? cards}) => planner.plan(
    learner: learner,
    cards: cards ?? this.cards,
    now: now,
    seed: seed ?? this.seed,
    newCandidates: newCandidates,
    optionCandidates: options,
    links: zz.links,
    available: available,
    partnerAvailable: partnerAvailable,
  );

  Duration get budget {
    final daily = learner.dailyBudget;
    final offered = available != null && available! < daily
        ? available!
        : daily;
    final left = offered - learner.spentToday;
    return left.isNegative ? Duration.zero : left;
  }
}

List<World> worlds(int count, {int idleDays = 0}) {
  final random = Random(20260615 + idleDays);
  return [for (var i = 0; i < count; i++) World(random, idleDays: idleDays)];
}

void main() {
  group('Planner properties (docs/05-session-planner.md §8)', () {
    final random = worlds(300);

    test('1: the estimate never exceeds the budget (I-13)', () {
      for (final world in random) {
        final plan = world.plan();
        expect(plan.budget, world.budget);
        expect(plan.estimate, lessThanOrEqualTo(plan.budget));
        final newItemTime =
            config.introductionDuration +
            config.cardDuration[plan.newCardMode]!;
        expect(
          plan.estimate,
          reviewTime(plan.reviews) +
              newItemTime * plan.newItems.length +
              (plan.options.isEmpty
                  ? Duration.zero
                  : plan.options.first.duration),
        );
      }
    });

    test('a used-up budget is enough for today', () {
      final spent = random.where((w) => w.budget == Duration.zero).toList();
      expect(spent, isNotEmpty);
      for (final world in spent) {
        expect(
          world.plan(),
          const TodayPlan(budget: Duration.zero, enough: true),
        );
      }
    });

    test('2: no new items when reviews fill 80% of the cap (I-07)', () {
      var loaded = 0;
      for (final world in random) {
        final plan = world.plan();
        if (plan.enough) continue;
        if (plan.projectedDailyReview > plan.reviewCap * config.newLoadShare) {
          loaded++;
          expect(plan.newItems, isEmpty);
        }
        expect(
          plan.newItems.length + world.learner.newToday,
          lessThanOrEqualTo(
            max(config.maxNew[world.learner.level]!, world.learner.newToday),
          ),
        );
        final taken = {for (final card in world.cards) card.itemKey};
        expect(plan.newItems.where(taken.contains), isEmpty);
      }
      expect(loaded, greaterThan(10));
    });

    test('6: a minimum day has reviews only', () {
      final short = [
        for (final world in random)
          if (world.budget > Duration.zero &&
              world.budget <= config.minimumDayBudget)
            world,
      ];
      expect(short, isNotEmpty);
      for (final world in short) {
        final plan = world.plan();
        expect(plan.minimumDay, isTrue);
        expect(plan.newItems, isEmpty);
        expect(plan.options, isEmpty);
        expect(reviewTime(plan.reviews), lessThanOrEqualTo(world.budget));
      }
    });

    test('7: after a week away reviews stay under the cap, nothing new', () {
      var backlogs = 0;
      for (final world in worlds(150, idleDays: 9)) {
        final plan = world.plan();
        if (plan.enough) continue;
        expect(reviewTime(plan.reviews), lessThanOrEqualTo(plan.reviewCap));
        expect(
          plan.reviewCap,
          lessThanOrEqualTo(plan.minimumDay ? world.budget : config.reviewCap),
        );
        if (plan.backlog) {
          backlogs++;
          expect(plan.newItems, isEmpty);
        }
      }
      expect(backlogs, greaterThan(30));
    });

    test('9: the same input and seed give the same plan', () {
      var reordered = 0;
      for (final world in random) {
        final plan = world.plan();
        expect(world.plan(), plan);
        // The order the cards arrive in does not matter.
        final shuffled = [...world.cards]..shuffle(Random(1));
        expect(world.plan(cards: shuffled), plan);
        // Another seed draws another order within a priority slice.
        final other = world.plan(seed: world.seed + 1);
        expect(other.reviews.toSet(), hasLength(other.reviews.length));
        if (!_sameOrder(other.reviews, plan.reviews)) reordered++;
      }
      expect(reordered, greaterThan(50));
    });

    test('reviews are due cards, each once', () {
      for (final world in random) {
        final plan = world.plan();
        expect(plan.reviews.toSet(), hasLength(plan.reviews.length));
        for (final card in plan.reviews) {
          expect(card.memory.due.isAfter(now), isFalse);
        }
      }
    });

    test('options: none, or two to three that fit, two a strand at most', () {
      var offered = 0;
      for (final world in random) {
        final plan = world.plan();
        if (plan.options.isEmpty) continue;
        offered++;
        expect(plan.options.length, inInclusiveRange(2, 3));
        final left =
            plan.budget - (plan.estimate - plan.options.first.duration);
        expect(left, greaterThanOrEqualTo(config.optionsMinimum));
        for (final option in plan.options) {
          expect(option.duration, lessThanOrEqualTo(left));
          expect(world.options, contains(option));
          expect(
            plan.options.where((o) => o.strand == option.strand).length,
            lessThanOrEqualTo(Planner.mostPerStrand),
          );
        }
      }
      expect(offered, greaterThan(30));
    });
  });

  group('Planner reviews', () {
    const learner = LearnerSnapshot(level: CefrLevel.a1);

    test('the more forgotten card comes first', () {
      final fading = card(1, daysAgo: 40);
      final recent = card(2, daysAgo: 4.5);
      expect(
        planner.priority(fading, now),
        greaterThan(planner.priority(recent, now) + 0.1),
      );
      final plan = planner.plan(
        learner: learner,
        cards: [recent, fading],
        now: now,
        seed: 7,
      );
      expect(plan.reviews, [fading, recent]);
    });

    test('spoken production weighs most, the weekly focus adds to it', () {
      final spoken = card(1, daysAgo: 20);
      final heard = card(2, daysAgo: 20, mode: CardMode.recognizeAudio);
      final focused = card(3, daysAgo: 20, focus: true);
      expect(
        planner.priority(spoken, now),
        greaterThan(planner.priority(heard, now)),
      );
      expect(
        planner.priority(focused, now) - planner.priority(spoken, now),
        closeTo(config.focusBonus, 1e-9),
      );
    });

    test('cards that are not due are left alone', () {
      final notDue = card(1, daysAgo: 1);
      expect(notDue.memory.due.isAfter(now), isTrue);
      final plan = planner.plan(
        learner: learner,
        cards: [notDue],
        now: now,
        seed: 1,
      );
      expect(plan.reviews, isEmpty);
      expect(plan.backlog, isFalse);
    });

    test('the block stops at the cap: 10 minutes or 40% of the budget', () {
      final many = [for (var i = 0; i < 100; i++) card(i, daysAgo: 30)];
      TodayPlan planFor(Duration daily) => planner.plan(
        learner: LearnerSnapshot(level: CefrLevel.a1, dailyBudget: daily),
        cards: many,
        now: now,
        seed: 1,
      );
      final long = planFor(minutes(30));
      expect(long.reviewCap, minutes(10));
      expect(long.reviews, hasLength(30));
      expect(long.backlog, isTrue);
      final short = planFor(minutes(15));
      expect(short.reviewCap, minutes(6));
      expect(short.reviews, hasLength(18));
    });

    test('a due contrast pair is reviewed together, never back to back', () {
      final pair = zz.links.firstWhere(
        (link) => link.type == LinkType.contrastsWith,
      );
      final first = card(1, daysAgo: 30, itemKey: pair.from);
      final second = card(2, daysAgo: 30, itemKey: pair.to);
      final others = [
        for (var i = 3; i < 60; i++) card(i, daysAgo: 30, itemKey: 'other-$i'),
      ];
      for (var seed = 0; seed < 40; seed++) {
        final plan = planner.plan(
          learner: learner,
          cards: [first, second, ...others],
          now: now,
          seed: seed,
          links: zz.links,
        );
        final a = plan.reviews.indexOf(first);
        final b = plan.reviews.indexOf(second);
        // One in the block brings the other in.
        expect(a >= 0, b >= 0, reason: 'seed $seed');
        if (a >= 0) expect((a - b).abs(), greaterThan(1), reason: 'seed $seed');
        expect(reviewTime(plan.reviews), lessThanOrEqualTo(plan.reviewCap));
      }
    });

    test('a pair is not split up to make room for another pair', () {
      const links = [
        ItemLink(from: 'a1', to: 'a2', type: LinkType.contrastsWith),
        ItemLink(from: 'b1', to: 'b2', type: LinkType.contrastsWith),
      ];
      final pairs = [
        for (final (i, key) in ['a1', 'a2', 'b1', 'b2'].indexed)
          card(i, daysAgo: 30, itemKey: key),
      ];
      final others = [
        for (var i = 4; i < 60; i++) card(i, daysAgo: 30, itemKey: 'other-$i'),
      ];
      for (var seed = 0; seed < 60; seed++) {
        final reviews = planner
            .plan(
              learner: learner,
              cards: [...pairs, ...others],
              now: now,
              seed: seed,
              links: links,
            )
            .reviews;
        final at = [for (final card in pairs) reviews.indexOf(card)];
        for (final (one, other) in [(at[0], at[1]), (at[2], at[3])]) {
          expect(one >= 0, other >= 0, reason: 'seed $seed');
          if (one >= 0) expect((one - other).abs(), greaterThan(1));
        }
        expect(reviews, hasLength(30));
      }
    });

    test('a pair at the end of a short block is parted too', () {
      const links = [
        ItemLink(from: 'a1', to: 'a2', type: LinkType.contrastsWith),
      ];
      final first = card(1, daysAgo: 12, itemKey: 'a1');
      final second = card(2, daysAgo: 12, itemKey: 'a2');
      final faded = card(3, daysAgo: 60, itemKey: 'other');
      final three = planner.plan(
        learner: learner,
        cards: [first, second, faded],
        now: now,
        seed: 1,
        links: links,
      );
      // By priority the faded card would lead; it goes between the pair.
      expect(three.reviews[1], faded);
      // Two cards alone cannot be parted.
      final two = planner.plan(
        learner: learner,
        cards: [first, second],
        now: now,
        seed: 1,
        links: links,
      );
      expect(two.reviews, hasLength(2));
    });
  });

  group('Planner new items (docs/05 §3, lines 10–14)', () {
    final candidates = [for (final sense in senses) sense.key];
    TodayPlan planFor(LearnerSnapshot learner, {List<PlanCard>? cards}) =>
        planner.plan(
          learner: learner,
          cards: cards ?? const [],
          now: now,
          seed: 1,
          newCandidates: candidates,
        );

    test('as many as 80% of the review cap leaves room for', () {
      // (0.8 × 10 min − 0) / 1.2 min = 6.67.
      final plan = planFor(const LearnerSnapshot(level: CefrLevel.a1));
      expect(plan.newItems, candidates.take(6));
      // A smaller budget has a smaller cap: 0.8 × 3.2 min / 1.2 min.
      final small = planFor(
        LearnerSnapshot(level: CefrLevel.a1, dailyBudget: minutes(8)),
      );
      expect(small.newItems, hasLength(2));
    });

    test('never more than the level allows', () {
      final plan =
          Planner(
            config: const PlannerConfig(
              newCardDailyCost: Duration(seconds: 10),
            ),
          ).plan(
            learner: const LearnerSnapshot(level: CefrLevel.a0),
            cards: const [],
            now: now,
            seed: 1,
            newCandidates: candidates,
          );
      expect(plan.newItems, hasLength(config.maxNew[CefrLevel.a0]));
    });

    test('the day cap counts the items introduced earlier today', () {
      final generous = Planner(
        config: const PlannerConfig(newCardDailyCost: Duration(seconds: 10)),
      );
      TodayPlan after(int newToday) => generous.plan(
        learner: LearnerSnapshot(level: CefrLevel.a0, newToday: newToday),
        cards: const [],
        now: now,
        seed: 1,
        newCandidates: candidates,
      );
      final cap = config.maxNew[CefrLevel.a0]!;
      expect(after(2).newItems, hasLength(cap - 2));
      expect(after(cap).newItems, isEmpty);
      expect(after(cap + 3).newItems, isEmpty);
    });

    test('halved when first-try recalls fall under 70% (P10)', () {
      final plan = planFor(
        const LearnerSnapshot(level: CefrLevel.a1, recentUnaidedAccuracy: 0.69),
      );
      expect(plan.newItems, hasLength(3));
      final fine = planFor(
        const LearnerSnapshot(level: CefrLevel.a1, recentUnaidedAccuracy: 0.7),
      );
      expect(fine.newItems, hasLength(6));
    });

    test('fewer as the coming week fills with reviews', () {
      // 84 spoken cards due this week: 84 × 20 s / 7 days = 4 min a day.
      final coming = [for (var i = 0; i < 84; i++) card(i, daysAgo: 2)];
      expect(coming.every((c) => c.memory.due.isAfter(now)), isTrue);
      final plan = planFor(
        const LearnerSnapshot(level: CefrLevel.a1),
        cards: coming,
      );
      expect(plan.projectedDailyReview, minutes(4));
      // (8 − 4) / 1.2 = 3.33.
      expect(plan.newItems, hasLength(3));
    });

    test('none of an item that already has a card', () {
      final known = card(1, daysAgo: 1, itemKey: candidates.first);
      final plan = planFor(
        const LearnerSnapshot(level: CefrLevel.a1),
        cards: [known],
      );
      expect(plan.newItems, isNot(contains(candidates.first)));
      expect(plan.newItems.first, candidates[1]);
    });

    test('the first card is spoken, or typed in silent mode (I-05)', () {
      final spoken = planFor(const LearnerSnapshot(level: CefrLevel.a1));
      expect(spoken.newCardMode, CardMode.speak);
      final silent = planFor(
        const LearnerSnapshot(level: CefrLevel.a1, silentMode: true),
      );
      expect(silent.newCardMode, CardMode.type);
    });
  });

  group('Planner options (docs/05 §3, lines 15–21)', () {
    PlanOption option(
      String activity,
      Strand strand, {
      num duration = 6,
      bool together = false,
    }) => PlanOption(
      activity: activity,
      strand: strand,
      duration: minutes(duration),
      together: together,
    );

    TodayPlan planFor(
      List<PlanOption> candidates, {
      LearnerSnapshot learner = const LearnerSnapshot(level: CefrLevel.a1),
      bool partnerAvailable = false,
    }) => planner.plan(
      learner: learner,
      cards: const [],
      now: now,
      seed: 1,
      optionCandidates: candidates,
      partnerAvailable: partnerAvailable,
    );

    test('the strand furthest behind its weekly target comes first', () {
      // A1 targets of a 150-minute week: language 60, input 37.5,
      // output 30, fluency 22.5 minutes.
      final plan = planFor(
        [
          option('speaking_task', Strand.output),
          option('graded_reading', Strand.input),
          option('shadowing', Strand.fluency),
          option('error_focus', Strand.language),
        ],
        learner: LearnerSnapshot(
          level: CefrLevel.a1,
          weekStrandTime: {Strand.language: minutes(55)},
        ),
      );
      expect(plan.options.map((o) => o.activity), [
        'graded_reading',
        'speaking_task',
        'shadowing',
      ]);
    });

    test('an option with the partner leads when the partner is there', () {
      final candidates = [
        option('speaking_task', Strand.output),
        option('graded_reading', Strand.input),
        option('pair_chat_card', Strand.output, together: true),
      ];
      expect(
        planFor(candidates, partnerAvailable: true).options.first.activity,
        'pair_chat_card',
      );
      expect(
        planFor(candidates).options.first.activity,
        isNot('pair_chat_card'),
      );
    });

    test('never one option alone (I-14)', () {
      expect(
        planFor([option('speaking_task', Strand.output)]).options,
        isEmpty,
      );
      final two = planFor([
        option('speaking_task', Strand.output),
        option('writing_task', Strand.output, duration: 40),
        option('shadowing', Strand.fluency),
      ]);
      expect(two.options, hasLength(2));
    });

    test('no options with under five minutes left', () {
      final candidates = [
        option('shadowing', Strand.fluency, duration: 4),
        option('minimal_pairs', Strand.language, duration: 3),
      ];
      // 7.5 minutes is more than a minimum day; nine reviews take three
      // of them (the cap), which leaves four and a half.
      TodayPlan planWith(Duration daily) => planner.plan(
        learner: LearnerSnapshot(level: CefrLevel.a1, dailyBudget: daily),
        cards: [for (var i = 0; i < 30; i++) card(i, daysAgo: 30)],
        now: now,
        seed: 1,
        optionCandidates: candidates,
      );
      final tight = planWith(minutes(7.5));
      expect(tight.minimumDay, isFalse);
      expect(tight.budget - tight.estimate, minutes(4.5));
      expect(tight.options, isEmpty);
      // Half a minute more and both options fit.
      expect(planWith(minutes(8)).options, hasLength(2));
    });
  });

  test('SeededRandom repeats itself for a seed and covers its range', () {
    List<int> draws(int seed) {
      final random = SeededRandom(seed);
      return [for (var i = 0; i < 200; i++) random.nextInt(10)];
    }

    expect(draws(42), draws(42));
    expect(draws(42), isNot(draws(43)));
    expect(draws(0).toSet(), hasLength(10));
    expect(draws(-5).every((n) => n >= 0 && n < 10), isTrue);
  });
}

bool _sameOrder(List<PlanCard> a, List<PlanCard> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
