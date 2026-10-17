import 'dart:async';

import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:dilbaz_app/features/together/application/together_controller.dart';
import 'package:dilbaz_app/features/together/application/together_view.dart';
import 'package:dilbaz_app/features/together/presentation/week_goal.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Together tab (docs/09 §5.9, F2-07): the partner and whether they have
/// the app open, today's invitations and the chat cards. Who did more is
/// never shown; an unanswered invitation is never pressed (I-12).
class TogetherScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final view = ref.watch(togetherProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabTogether)),
      body: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(teamProvider);
          return ref.refresh(togetherProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          // The end scrolls clear of the "Söyleyemedim" button.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          child: switch (view) {
            AsyncData(value: TogetherReady() && final ready) => _Ready(
              view: ready,
            ),
            AsyncData(value: TogetherAlone(:final teamName)) => Text(
              l10n.togetherAlone(teamName),
            ),
            AsyncData(value: TogetherNoTeam()) => Text(l10n.togetherNoTeam),
            AsyncData(value: TogetherUnavailable()) => Text(
              l10n.sectionInPreparation,
            ),
            AsyncData(value: TogetherOffline()) || AsyncError() => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                Text(l10n.togetherOffline),
                OutlinedButton(
                  onPressed: () {
                    ref
                      ..invalidate(teamProvider)
                      ..invalidate(togetherProvider);
                  },
                  child: Text(l10n.togetherRetry),
                ),
              ],
            ),
            AsyncLoading() => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _Ready extends ConsumerWidget {
  const new({required this.view});

  final TogetherReady view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final actions = ref.read(togetherActionsProvider.notifier);
    final failed = ref.watch(togetherActionsProvider) != null;
    final partner = view.partner.name;
    final outgoing = view.outgoing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Row(
          spacing: 12,
          children: [
            Icon(
              view.partnerHere ? Icons.circle : Icons.circle_outlined,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            Expanded(
              child: Text(
                view.partnerHere
                    ? l10n.togetherPartnerHere(partner)
                    : l10n.togetherPartnerAway(partner),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (view.cheer case final cheer?)
          _Note(
            text: l10n.cheerReceived(partner, cheerText(l10n, cheer.key)),
            actions: const [],
          ),
        if (view.week case final week?)
          WeekGoal(week: week, self: view.self, partner: view.partner),
        if (view.incoming case (:final invite, :final card))
          _Note(
            text: l10n.togetherIncoming(partner, card.title),
            actions: [
              FilledButton(
                onPressed: () async {
                  await actions.answer(invite, yes: true);
                  if (context.mounted) {
                    unawaited(context.push(AppRoutes.chatCardOf(card.key)));
                  }
                },
                child: Text(l10n.togetherYes),
              ),
              TextButton(
                onPressed: () => unawaited(actions.answer(invite, yes: false)),
                child: Text(l10n.togetherNotNow),
              ),
            ],
          )
        else if (view.agreed case final card?)
          _Note(
            text: l10n.togetherAgreed(card.title),
            actions: [
              FilledButton(
                onPressed: () => context.push(AppRoutes.chatCardOf(card.key)),
                child: Text(l10n.togetherOpenCard),
              ),
            ],
          )
        else if (outgoing case (:final invite, :final card))
          _Note(
            text: switch (invite.state) {
              InviteState.accepted => l10n.togetherSentAccepted(
                partner,
                card.title,
              ),
              InviteState.declined => l10n.togetherSentDeclined(partner),
              _ => l10n.togetherSent(card.title),
            },
            actions: [
              if (invite.state == InviteState.sent)
                TextButton(
                  onPressed: () => unawaited(actions.cancel(invite)),
                  child: Text(l10n.togetherCancel),
                ),
            ],
          ),
        if (view.gap case (:final session, :final task))
          _Note(
            text: session.createdBy == view.self
                ? l10n.gapOpenMine(task.title)
                : l10n.gapOpenPartner(partner, task.title),
            actions: [
              FilledButton(
                onPressed: () => context.push(AppRoutes.infoGapOf(session.id)),
                child: Text(l10n.gapOpen),
              ),
            ],
          ),
        if (failed) Text(l10n.togetherFailed),
        Text(l10n.gapTasksTitle, style: theme.textTheme.titleLarge),
        Text(l10n.gapTasksNote),
        for (final task in view.gaps)
          Card.outlined(
            margin: EdgeInsets.zero,
            child: ListTile(
              title: Text(task.title),
              subtitle: Text(task.prompt),
              trailing: const Icon(Icons.chevron_right),
              enabled: view.gap == null,
              onTap: () async {
                final id = await actions.startGap(task);
                if (id != null && context.mounted) {
                  unawaited(context.push(AppRoutes.infoGapOf(id)));
                }
              },
            ),
          ),
        Text(l10n.togetherCardsTitle, style: theme.textTheme.titleLarge),
        Text(l10n.togetherCardsNote),
        for (final card in view.cards)
          Card.outlined(
            margin: EdgeInsets.zero,
            child: ListTile(
              title: Text(card.title),
              subtitle: Text(card.question),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.chatCardOf(card.key)),
            ),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const new({required this.text, required this.actions});

  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card.filled(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(text, style: Theme.of(context).textTheme.bodyLarge),
          if (actions.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    ),
  );
}
