import 'dart:async';

import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/features/together/application/together_controller.dart';
import 'package:dilbaz_app/features/together/application/together_view.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// On Today: the partner's invitation waiting for an answer, or the chat
/// card the two agreed on today, as the suggested thing to do (docs/05
/// §6). Nothing when offline or alone.
class TogetherTodayCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final view = ref.watch(togetherProvider).value;
    if (view is! TogetherReady) return const SizedBox.shrink();
    final actions = ref.read(togetherActionsProvider.notifier);
    final (String text, List<Widget> buttons) = switch (view) {
      TogetherReady(incoming: (:final invite, :final card)) => (
        l10n.togetherIncoming(view.partner.name, card.title),
        [
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
      ),
      TogetherReady(agreed: final card?) => (
        l10n.togetherAgreed(card.title),
        [
          FilledButton(
            onPressed: () => context.push(AppRoutes.chatCardOf(card.key)),
            child: Text(l10n.togetherOpenCard),
          ),
        ],
      ),
      _ => ('', const <Widget>[]),
    };
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card.filled(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                spacing: 12,
                children: [
                  const Icon(Icons.favorite_border),
                  Expanded(child: Text(text)),
                ],
              ),
              Wrap(spacing: 8, runSpacing: 8, children: buttons),
            ],
          ),
        ),
      ),
    );
  }
}
