import 'package:dilbaz_engine/src/curriculum/item_link.dart';
import 'package:dilbaz_engine/src/curriculum/link_type.dart';
import 'package:dilbaz_engine/src/fsrs/card_mode.dart';
import 'package:dilbaz_engine/src/fsrs/mode_group.dart';
import 'package:dilbaz_engine/src/fsrs/srs_scheduler.dart';
import 'package:dilbaz_engine/src/model/learner_snapshot.dart';
import 'package:dilbaz_engine/src/planner/plan_card.dart';
import 'package:dilbaz_engine/src/planner/plan_option.dart';
import 'package:dilbaz_engine/src/planner/planner_config.dart';
import 'package:dilbaz_engine/src/planner/seeded_random.dart';
import 'package:dilbaz_engine/src/planner/strand.dart';
import 'package:dilbaz_engine/src/planner/today_plan.dart';

/// The session planner behind the Today screen
/// (docs/05-session-planner.md §3).
///
/// Within the day's budget (I-13) it proposes the reviews memory needs
/// most, as many new items as the review load allows (I-07) and a few
/// options to choose from (I-14). It is pure: the same inputs and seed give
/// the same plan, whatever order the inputs come in.
final class Planner {
  /// A planner with [config]. `schedulers` hold the FSRS weights of the
  /// mode groups; a group without one uses the defaults.
  new({this.config = const PlannerConfig(), this._schedulers = const {}});

  /// Days the projected review load is averaged over.
  static const projectionDays = 7;

  /// Most options offered; fewer than [leastOptions] means none.
  static const mostOptions = 3;

  /// Fewest options offered (I-14).
  static const leastOptions = 2;

  /// Most options of one strand.
  static const mostPerStrand = 2;

  static final _defaultScheduler = SrsScheduler();

  /// The planner's settings.
  final PlannerConfig config;

  final Map<ModeGroup, SrsScheduler> _schedulers;

  /// Today's plan at [now] (UTC).
  ///
  /// [cards] are all active cards; the planner finds the due ones.
  /// [newCandidates] are item keys in curriculum order. [links] give the
  /// contrast pairs. [available] is what the learner said they have today,
  /// when less than the daily budget.
  TodayPlan plan({
    required LearnerSnapshot learner,
    required Iterable<PlanCard> cards,
    required DateTime now,
    required int seed,
    Iterable<String> newCandidates = const [],
    Iterable<PlanOption> optionCandidates = const [],
    Iterable<ItemLink> links = const [],
    Duration? available,
    bool partnerAvailable = false,
  }) {
    final daily = learner.dailyBudget;
    final offered = available != null && available < daily ? available : daily;
    final budget = offered - learner.spentToday;
    if (budget <= Duration.zero) {
      return const TodayPlan(budget: Duration.zero, enough: true);
    }
    final minimumDay = budget <= config.minimumDayBudget;
    final share = budget * config.reviewShare;
    final reviewCap = minimumDay
        ? budget
        : (config.reviewCap < share ? config.reviewCap : share);

    final all = cards.toList();
    final due = [
      for (final card in all)
        if (!card.memory.due.isAfter(now)) card,
    ];
    final contrasts = _contrasts(links);
    final ordered = _byPriority(due, now, seed);
    final reviews = _fill(ordered, reviewCap);
    _pullInContrasts(reviews, ordered, reviewCap, contrasts);
    _separateContrasts(reviews, contrasts);
    final reviewTime = _time(reviews);

    final horizon = now.add(const Duration(days: projectionDays));
    final projected =
        _time(all.where((card) => !card.memory.due.isAfter(horizon))) ~/
        projectionDays;
    final plan = TodayPlan(
      budget: budget,
      reviews: reviews,
      estimate: reviewTime,
      minimumDay: minimumDay,
      reviewCap: reviewCap,
      projectedDailyReview: projected,
      backlog: _time(due) > reviewCap,
    );
    if (minimumDay) return plan;

    final newCardMode = learner.silentMode ? CardMode.type : CardMode.speak;
    final newItemTime = config.introductionDuration + _duration(newCardMode);
    final known = {for (final card in all) card.itemKey};
    final newItems = [
      for (final key in newCandidates)
        if (!known.contains(key)) key,
    ].take(_newCount(plan, learner, budget - reviewTime, newItemTime)).toList();
    final newTime = newItemTime * newItems.length;

    final options = _options(
      optionCandidates,
      learner,
      budget - reviewTime - newTime,
      partnerAvailable: partnerAvailable,
    );
    return plan.copyWith(
      newItems: newItems,
      newCardMode: newCardMode,
      options: options,
      estimate:
          reviewTime +
          newTime +
          (options.isEmpty ? Duration.zero : options.first.duration),
    );
  }

  /// Review priority: how much of the card is forgotten, weighted by its
  /// mode, plus the focus bonus.
  double priority(PlanCard card, DateTime now) {
    final scheduler = _schedulers[card.mode.group] ?? _defaultScheduler;
    final forgotten = 1 - scheduler.retrievability(card.memory, at: now);
    return forgotten * (config.modeWeight[card.mode] ?? 1) +
        (card.focus ? config.focusBonus : 0);
  }

  /// Highest priority first; within a tenth of priority the order is
  /// drawn from the seed, so modes and items interleave (P12).
  List<PlanCard> _byPriority(List<PlanCard> due, DateTime now, int seed) {
    final random = SeededRandom(seed);
    final keyed =
        [
          for (final card in [...due]..sort((a, b) => a.id.compareTo(b.id)))
            (
              card: card,
              slice: (priority(card, now) * 10).floor(),
              draw: random.nextInt(1 << 30),
            ),
        ]..sort((a, b) {
          final bySlice = b.slice.compareTo(a.slice);
          if (bySlice != 0) return bySlice;
          final byDraw = a.draw.compareTo(b.draw);
          return byDraw != 0 ? byDraw : a.card.id.compareTo(b.card.id);
        });
    return [for (final entry in keyed) entry.card];
  }

  /// The cards of [ordered] that fit in [cap], in order.
  List<PlanCard> _fill(List<PlanCard> ordered, Duration cap) {
    final chosen = <PlanCard>[];
    var time = Duration.zero;
    for (final card in ordered) {
      final next = time + _duration(card.mode);
      if (next > cap) continue;
      chosen.add(card);
      time = next;
    }
    return chosen;
  }

  /// Item key → the items it is easily confused with.
  static Map<String, Set<String>> _contrasts(Iterable<ItemLink> links) {
    final contrasts = <String, Set<String>>{};
    for (final link in links) {
      if (link.type != LinkType.contrastsWith) continue;
      (contrasts[link.from] ??= {}).add(link.to);
      (contrasts[link.to] ??= {}).add(link.from);
    }
    return contrasts;
  }

  /// When one of a due contrast pair is in the block, its partner joins
  /// it: confusable items are practised mixed (I-10). In a full block the
  /// partner takes the place of the last card that has no partner there.
  void _pullInContrasts(
    List<PlanCard> reviews,
    List<PlanCard> ordered,
    Duration cap,
    Map<String, Set<String>> contrasts,
  ) {
    if (contrasts.isEmpty) return;
    bool paired(PlanCard card) {
      final partners = contrasts[card.itemKey];
      return partners != null &&
          reviews.any((other) => partners.contains(other.itemKey));
    }

    for (final card in [...reviews]) {
      final partners = contrasts[card.itemKey];
      if (partners == null) continue;
      for (final other in ordered) {
        if (!partners.contains(other.itemKey) || reviews.contains(other)) {
          continue;
        }
        reviews.add(other);
        if (_time(reviews) <= cap) continue;
        final spare = reviews.lastIndexWhere(
          (c) => c != other && c != card && !paired(c),
        );
        if (spare >= 0) reviews.removeAt(spare);
        if (_time(reviews) > cap) reviews.remove(other);
      }
    }
  }

  /// Keeps at least one card between the two of a contrast pair.
  void _separateContrasts(
    List<PlanCard> reviews,
    Map<String, Set<String>> contrasts,
  ) {
    bool confusable(PlanCard a, PlanCard b) =>
        contrasts[a.itemKey]?.contains(b.itemKey) ?? false;
    void swap(int i, int j) {
      final card = reviews[i];
      reviews[i] = reviews[j];
      reviews[j] = card;
    }

    for (var i = 0; i + 1 < reviews.length; i++) {
      if (!confusable(reviews[i], reviews[i + 1])) continue;
      if (i + 2 < reviews.length) {
        swap(i + 1, i + 2);
      } else if (i > 0) {
        swap(i, i - 1);
      }
    }
  }

  /// How many new items today (docs/05 §3, lines 10–13).
  int _newCount(
    TodayPlan plan,
    LearnerSnapshot learner,
    Duration timeLeft,
    Duration newItemTime,
  ) {
    if (plan.backlog) return 0;
    final room = plan.reviewCap * config.newLoadShare;
    final spare = room - plan.projectedDailyReview;
    // The level's cap is per day: items introduced earlier today count.
    final left = (config.maxNew[learner.level] ?? 0) - learner.newToday;
    var count = (spare.inMicroseconds / config.newCardDailyCost.inMicroseconds)
        .floor()
        .clamp(0, left < 0 ? 0 : left);
    final accuracy = learner.recentUnaidedAccuracy;
    if (accuracy != null && accuracy < config.lowAccuracyThreshold) {
      count ~/= 2;
    }
    final fits = timeLeft.inMicroseconds ~/ newItemTime.inMicroseconds;
    return count < fits ? count : fits;
  }

  /// Up to three options that fit in [timeLeft], the strand furthest
  /// behind its weekly target first; none unless there are at least two.
  List<PlanOption> _options(
    Iterable<PlanOption> candidates,
    LearnerSnapshot learner,
    Duration timeLeft, {
    required bool partnerAvailable,
  }) {
    if (timeLeft < config.optionsMinimum) return const [];
    final weekly = learner.dailyBudget * config.weeklyDaysGoal;
    final targets = config.strandTargets[learner.level] ?? const {};
    double gap(Strand strand) {
      final target = weekly * (targets[strand] ?? 0);
      final spent = learner.weekStrandTime[strand] ?? Duration.zero;
      final behind = (target - spent).inMicroseconds;
      return behind > 0 ? behind.toDouble() : 0;
    }

    final largest = Strand.values.map(gap).reduce((a, b) => a > b ? a : b);
    double score(PlanOption option) =>
        (largest == 0 ? 0 : gap(option.strand) / largest) +
        (option.supportsUnprovenCanDo ? 0.5 : 0) +
        (option.focus ? 0.4 : 0) +
        (option.fresh ? 0.3 : 0) +
        (option.together && partnerAvailable ? 0.6 : 0);
    String name(PlanOption option) => '${option.activity}|${option.ref ?? ''}';

    final fitting =
        [
          for (final option in candidates)
            if (option.duration <= timeLeft) option,
        ]..sort((a, b) {
          final byScore = score(b).compareTo(score(a));
          return byScore != 0 ? byScore : name(a).compareTo(name(b));
        });
    final chosen = <PlanOption>[];
    final perStrand = <Strand, int>{};
    for (final option in fitting) {
      if (chosen.length == mostOptions) break;
      final count = perStrand[option.strand] ?? 0;
      if (count == mostPerStrand) continue;
      perStrand[option.strand] = count + 1;
      chosen.add(option);
    }
    return chosen.length < leastOptions ? const [] : chosen;
  }

  Duration _duration(CardMode mode) =>
      config.cardDuration[mode] ?? Duration.zero;

  Duration _time(Iterable<PlanCard> cards) =>
      cards.fold(Duration.zero, (total, card) => total + _duration(card.mode));
}
