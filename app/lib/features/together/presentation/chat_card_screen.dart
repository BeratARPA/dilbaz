import 'dart:async';
import 'dart:math';

import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:dilbaz_app/features/together/application/chat_card_controller.dart';
import 'package:dilbaz_app/features/together/application/together_controller.dart';
import 'package:dilbaz_app/features/together/application/together_view.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A chat card (A14, docs/09 §5.9): a question, follow-ups and phrases,
/// talked about face to face; nothing is recorded. The partner can be
/// invited from here; at the end, what could not be said is one tap away.
class ChatCardScreen extends ConsumerWidget {
  const new({required this.cardKey, super.key});

  final String cardKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final provider = chatCardControllerProvider(cardKey);
    final state = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.togetherCardsTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: switch (state) {
            AsyncData(value: final ChatCardOpen open) => _Open(
              state: open,
              provider: provider,
            ),
            AsyncData(value: ChatCardDone(:final spent)) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                Text(
                  l10n.chatDone(max(1, (spent.inSeconds / 60).round())),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(l10n.chatDoneGap),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.pushReplacement(AppRoutes.gapCapture),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.gapCaptureButton),
                ),
                FilledButton(
                  onPressed: () => context.pop(),
                  child: Text(l10n.cardsClose),
                ),
              ],
            ),
            AsyncData() || AsyncError() => Text(l10n.sectionInPreparation),
            AsyncLoading() => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _Open extends ConsumerWidget {
  const new({required this.state, required this.provider});

  final ChatCardOpen state;
  final ChatCardControllerProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final card = state.card;
    final controller = ref.read(provider.notifier);
    final together = ref.watch(togetherProvider).value;
    // The partner can be asked when there is one, and no invitation waits
    // for an answer and none was agreed on today.
    final canInvite =
        together is TogetherReady &&
        together.incoming == null &&
        together.agreed == null &&
        together.outgoing?.invite.state != InviteState.sent;
    String? meaning(List<String> meanings, int i) =>
        state.meanings && i < meanings.length ? meanings[i] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Text(card.title, style: theme.textTheme.labelLarge),
        Semantics(
          header: true,
          child: Text(card.question, style: theme.textTheme.headlineSmall),
        ),
        if (state.meanings) Text(card.meaning),
        Text(l10n.chatNote, style: theme.textTheme.bodySmall),
        Text(l10n.chatFollowUps, style: theme.textTheme.titleMedium),
        for (final (i, question) in card.followUps.indexed)
          _Line(text: question, meaning: meaning(card.followUpMeanings, i)),
        Text(l10n.chatPhrases, style: theme.textTheme.titleMedium),
        for (final (i, phrase) in card.phrases.indexed)
          _Line(text: phrase, meaning: meaning(card.phraseMeanings, i)),
        if (state.startedAt == null) ...[
          if (canInvite)
            OutlinedButton.icon(
              onPressed: () => unawaited(
                ref.read(togetherActionsProvider.notifier).invite(card),
              ),
              icon: const Icon(Icons.favorite_border),
              label: Text(l10n.chatInvite),
            ),
          FilledButton(
            onPressed: controller.start,
            child: Text(l10n.chatStart),
          ),
        ] else ...[
          Text(l10n.chatTalking, style: theme.textTheme.titleMedium),
          FilledButton(
            onPressed: () => unawaited(controller.finish()),
            child: Text(l10n.chatFinish),
          ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const new({required this.text, this.meaning});

  final String text;
  final String? meaning;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(text, style: Theme.of(context).textTheme.bodyLarge),
      if (meaning case final meaning?)
        Text(meaning, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}
