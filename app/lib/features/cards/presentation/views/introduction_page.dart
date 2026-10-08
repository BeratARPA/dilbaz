import 'dart:async';

import 'package:dilbaz_app/features/cards/application/card_session_controller.dart';
import 'package:dilbaz_app/features/cards/application/card_session_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A new item before its first card (A00, docs/09 §5.4): the carrier
/// sentence with its clip, the meaning, and the notes; then "now you say
/// it". The answer is shown here, before any try: one of the two
/// exceptions of I-01.
class IntroductionPage extends ConsumerWidget {
  const new({required this.view, super.key});

  final IntroductionView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(cardSessionControllerProvider.notifier);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Text(
            l10n.cardsNew,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          Semantics(
            header: true,
            child: Text(view.headword, style: theme.textTheme.headlineMedium),
          ),
          Text(view.meaning, style: theme.textTheme.titleMedium),
          Card.outlined(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Text(
                    l10n.cardsSaySentence,
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(view.sentence, style: theme.textTheme.headlineSmall),
                  Text(view.sentenceMeaning, style: theme.textTheme.bodyLarge),
                  if (view.hasClip)
                    FilledButton.tonalIcon(
                      onPressed: view.playing
                          ? null
                          : () => unawaited(controller.play()),
                      icon: const Icon(Icons.volume_up),
                      label: Text(l10n.cardsListen),
                    ),
                ],
              ),
            ),
          ),
          if (view.usageNote case final note?)
            _Note(icon: Icons.info_outline, text: note),
          if (view.contrastNote case final note?)
            _Note(icon: Icons.compare_arrows, text: note),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: controller.begin,
              child: Text(
                view.input == AnswerInput.speak
                    ? l10n.cardsTrySpeak
                    : l10n.cardsTryType,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      Expanded(child: Text(text)),
    ],
  );
}
