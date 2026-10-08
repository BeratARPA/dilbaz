import 'dart:async';
import 'dart:math';

import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_app/features/content/presentation/content_status_view.dart';
import 'package:dilbaz_app/features/monthly/presentation/monthly_invitation_card.dart';
import 'package:dilbaz_app/features/placement/presentation/placement_invitation_card.dart';
import 'package:dilbaz_app/features/today/application/today_controller.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Today tab: the planner's suggestions (docs/09 §5.2). No streak, no
/// quota: what fits the time left, the week so far, and "enough for today"
/// once the time is up (I-12, I-13).
class TodayScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back in the app, maybe on another day: plan again.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(todayProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabToday)),
      body: ContentStatusView(
        ready: (context, content) => RefreshIndicator(
          onRefresh: () => ref.refresh(todayProvider.future),
          // A short page, built whole: everything on it can be found and
          // reached; it scrolls even when short, for the refresh.
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            // The end scrolls clear of the "Söyleyemedim" button.
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Greeting(),
                const PlacementInvitationCard(),
                const MonthlyInvitationCard(),
                const _Today(),
                const SizedBox(height: 24),
                Text(
                  l10n.contentReady(
                    content.words,
                    content.chunks,
                    content.sentences,
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Minutes as the learner reads them: rounded, at least one.
int _minutes(Duration time) => max(1, (time.inSeconds / 60).round());

class _Greeting extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final greeting = ref.watch(todayProvider).value?.greeting;
    if (greeting == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(switch (greeting) {
        TodayGreeting.morning => l10n.todayGreetingMorning,
        TodayGreeting.day => l10n.todayGreetingDay,
        TodayGreeting.evening => l10n.todayGreetingEvening,
      }, style: Theme.of(context).textTheme.headlineSmall),
    );
  }
}

class _Today extends ConsumerWidget {
  const new();

  /// Choices of "how much time do you have today" (docs/05 §6).
  static const _choices = [5, 15, 30];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final view = ref.watch(todayProvider).value;
    if (view == null) return const SizedBox.shrink();

    Future<void> open(String route) async {
      await context.push(route);
      // What was done there changes the plan.
      ref.invalidate(todayProvider);
    }

    final budget = view.dailyBudget.inMinutes;
    final selected = (view.chosen ?? view.dailyBudget).inMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        const SizedBox(height: 8),
        // Once the day is done, only a quiet way to go on is left.
        if (!view.enough) ...[
          Text(l10n.todayTimeQuestion, style: theme.textTheme.titleMedium),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Less than the budget, or the budget itself (docs/05 §6).
              for (final minutes in {
                ..._choices.where((m) => m < budget),
                budget,
              })
                ChoiceChip(
                  label: Text(l10n.todayMinutes(minutes)),
                  selected: selected == minutes,
                  onSelected: (_) => ref
                      .read(todayTimeProvider.notifier)
                      .choose(
                        minutes == budget ? null : Duration(minutes: minutes),
                      ),
                ),
            ],
          ),
        ],
        if (view.enough)
          _Enough(view: view, onMore: () => open(AppRoutes.cardsBeyondBudget))
        else
          _Cards(view: view, onStart: () => open(AppRoutes.cards)),
        _Week(view: view),
      ],
    );
  }
}

class _Cards extends StatelessWidget {
  const new({required this.view, required this.onStart});

  final TodayView view;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final any = view.reviews + view.newItems > 0;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(l10n.todayCardsTitle, style: theme.textTheme.titleMedium),
            if (view.backlog) Text(l10n.todayWelcomeBack),
            if (view.minimumDay) Text(l10n.todayMinimumDay),
            Text(
              any
                  ? l10n.todayCardsSummary(
                      view.reviews,
                      view.newItems,
                      _minutes(view.estimate),
                    )
                  : l10n.todayCardsNone,
              style: theme.textTheme.bodyLarge,
            ),
            if (any)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => unawaited(onStart()),
                  child: Text(l10n.todayCardsStart),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Bugünlük yeter" (docs/09 §5.14): what was done, see you tomorrow, and
/// a quiet way to go on.
class _Enough extends StatelessWidget {
  const new({required this.view, required this.onMore});

  final TodayView view;
  final Future<void> Function() onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final tomorrow = switch (view.anchor) {
      'morning_coffee' => l10n.todayTomorrowMorningCoffee,
      'lunch_break' => l10n.todayTomorrowLunchBreak,
      'after_dinner' => l10n.todayTomorrowAfterDinner,
      'before_bed' => l10n.todayTomorrowBeforeBed,
      _ => l10n.todayTomorrow,
    };
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(l10n.todayEnoughTitle, style: theme.textTheme.titleLarge),
            Text(l10n.todaySpent(_minutes(view.spentToday))),
            if (view.reviewedToday > 0)
              Text(l10n.cardsDoneReviewed(view.reviewedToday)),
            if (view.introducedToday > 0)
              Text(l10n.cardsDoneIntroduced(view.introducedToday)),
            Text(tomorrow),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => unawaited(onMore()),
                child: Text(l10n.todayGoOn),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The week's study days against the goal; no streak (I-12).
class _Week extends StatelessWidget {
  const new({required this.view});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final goal = view.weeklyGoal < 1 ? 1 : view.weeklyGoal;
    final label = l10n.todayWeek(view.daysThisWeek, view.weeklyGoal);
    return Row(
      spacing: 16,
      children: [
        SizedBox.square(
          dimension: 48,
          child: CircularProgressIndicator(
            value: (view.daysThisWeek / goal).clamp(0, 1).toDouble(),
            strokeWidth: 6,
            semanticsLabel: label,
          ),
        ),
        Expanded(child: Text(label)),
      ],
    );
  }
}
