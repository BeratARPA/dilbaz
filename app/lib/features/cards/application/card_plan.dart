import 'dart:math';

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/repositories/assessment_repository.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'card_plan.g.dart';

/// The planner's seed: the same all day for one learner (docs/05 §1).
/// Tests fix it.
@riverpod
int cardSeed(Ref ref) {
  final userId = ref.watch(authRepositoryProvider).userId ?? '';
  final day = ref.watch(clockProvider)().toLocal();
  var seed = 17;
  // Small steps keep it exact on the web too.
  for (final unit in '$userId|${day.year}-${day.month}-${day.day}'.codeUnits) {
    seed = (seed * 31 + unit) & 0x3FFFFFFF;
  }
  return seed;
}

/// What the learner said they have today ("bugün ne kadar vaktin var?",
/// docs/05 §6); it holds for the day it was chosen.
typedef ChosenTime = ({DateTime day, Duration available});

@Riverpod(keepAlive: true)
class TodayTime extends _$TodayTime {
  @override
  ChosenTime? build() => null;

  /// Today's time; null goes back to the daily budget.
  void choose(Duration? available) {
    final now = ref.read(clockProvider)();
    state = available == null
        ? null
        : (day: startOfLocalDay(now), available: available);
  }
}

/// Midnight of [now]'s day where the learner is, in UTC.
DateTime startOfLocalDay(DateTime now) {
  final local = now.toLocal();
  return DateTime(local.year, local.month, local.day).toUtc();
}

/// Midnight of the Monday of [now]'s week where the learner is, in UTC.
DateTime startOfLocalWeek(DateTime now) {
  final local = now.toLocal();
  return DateTime(
    local.year,
    local.month,
    local.day - (local.weekday - DateTime.monday),
  ).toUtc();
}

/// What the planner planned for the cards, and what it was given
/// (docs/05 §1): the Today screen shows it, a card session runs it.
typedef CardPlan = ({
  String userId,
  StudiedCourse course,
  StudySettings settings,
  TodayPlan plan,
  PackLanguage language,
  LemmaKnowledge knowledge,

  /// The course's cards by id.
  Map<String, StoredCard> cards,

  /// Time spent today and the items introduced today.
  Duration spentToday,
  int newToday,
});

/// Plans the cards now. [beyondBudget] plans as if nothing had been spent
/// today: the learner chose to go on after "Bugünlük yeter" (docs/05 §6).
/// Null before the welcome flow or the packs.
Future<CardPlan?> planCards(Ref ref, {bool beyondBudget = false}) async {
  final userId = ref.watch(authRepositoryProvider).userId;
  final assessments = ref.watch(assessmentRepositoryProvider);
  final profiles = ref.watch(profileRepositoryProvider);
  final content = ref.watch(cardContentRepositoryProvider);
  final cards = ref.watch(cardRepositoryProvider);
  final sessions = ref.watch(sessionRepositoryProvider);
  final now = ref.watch(clockProvider)();
  final seed = ref.watch(cardSeedProvider);
  final chosen = ref.watch(todayTimeProvider);
  if (userId == null) return null;
  final course = await assessments.course(userId);
  final settings = await profiles.studySettings(userId);
  final language = await content.language();
  if (course == null || settings == null || language == null) return null;

  final items = await content.items();
  final personal = await content.personalItems(course.id, course.level);
  final links = await content.links();
  final stored = await cards.cards(course.id);
  final evidence = await cards.evidence(course.id);
  final today = startOfLocalDay(now);
  final lately = today.subtract(const Duration(days: 2));
  final introducedToday = {
    for (final card in stored)
      if (!card.createdAt.isBefore(today)) card.itemRef,
  };
  final candidates = Curriculum(items: [...items, ...personal], links: links)
      .next(
        level: course.level,
        levelOf: (key) =>
            evidence[key]?.productionLevel(now: now) ?? ItemLevel.unseen,
        // What the learner asked for comes first (docs/02 §4.3).
        personal: {for (final item in personal) item.key},
        introducedToday: introducedToday,
        introducedLately: {
          for (final card in stored)
            if (!card.createdAt.isBefore(lately)) card.itemRef,
        },
      );
  final spent = await sessions.timeSince(course.id, today);
  final spentToday = spent.values.fold(Duration.zero, (a, b) => a + b);
  final plan = Planner().plan(
    learner: LearnerSnapshot(
      level: course.level,
      dailyBudget: settings.dailyBudget,
      spentToday: beyondBudget ? Duration.zero : spentToday,
      recentUnaidedAccuracy: await cards.unaidedAccuracySince(
        course.id,
        now.subtract(const Duration(days: 7)),
      ),
      weekStrandTime: await sessions.timeSince(
        course.id,
        startOfLocalWeek(now),
      ),
      silentMode: settings.silentMode,
      newToday: introducedToday.length,
    ),
    cards: [
      for (final card in stored)
        PlanCard(
          id: card.id,
          itemKey: card.itemRef,
          mode: card.mode,
          memory: card.memory,
        ),
    ],
    now: now,
    seed: seed,
    newCandidates: candidates,
    links: links,
    available: chosen != null && chosen.day == today ? chosen.available : null,
  );
  return (
    userId: userId,
    course: course,
    settings: settings,
    plan: plan,
    language: language,
    knowledge: LemmaKnowledge.fromCards(
      items: items,
      evidence: evidence,
      ranks: _ranks(items),
      xlex: await assessments.latestXlex(course.id),
    ),
    cards: {for (final card in stored) card.id: card},
    spentToday: spentToday,
    newToday: introducedToday.length,
  );
}

/// Lemma → its best frequency rank, for the lemmas' chance of being known.
Map<String, int> _ranks(List<ContentItem> items) {
  final ranks = <String, int>{};
  for (final item in items) {
    final rank = item.rank;
    if (item.kind != ItemKind.wordSense || rank == null) continue;
    for (final lemma in item.lemmas) {
      ranks[lemma] = min(rank, ranks[lemma] ?? rank);
    }
  }
  return ranks;
}
