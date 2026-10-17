import 'dart:async';

import 'package:dilbaz_app/data/repositories/card_feedback_repository.dart';
import 'package:dilbaz_app/features/cards/application/card_session_controller.dart';
import 'package:dilbaz_app/features/cards/application/card_session_state.dart';
import 'package:dilbaz_app/features/cards/presentation/views/content_report_sheet.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A listening card (A03): hear a word or a chunk, choose its meaning. The
/// choices open once it was heard; after the choice the right meaning is
/// marked and what was heard is shown. A wrong choice is never red (I-12).
class RecognizePage extends ConsumerWidget {
  const new({required this.session, required this.view, super.key});

  final CardSessionControllerProvider session;
  final RecognizeView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(session.notifier);
    final chosen = view.chosen;
    final right = view.right;
    Future<void> report(ReportReason reason, String? note) =>
        controller.report(reason, note: note);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.cardsRecognizeTitle,
              style: theme.textTheme.titleLarge,
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: view.playing ? null : () => unawaited(controller.play()),
            icon: Icon(view.heard ? Icons.replay : Icons.volume_up),
            label: Text(view.heard ? l10n.cardsListenAgain : l10n.cardsListen),
          ),
          if (!view.heard) Text(l10n.cardsRecognizeListenFirst),
          for (final (index, choice) in view.choices.indexed)
            _Choice(
              text: choice,
              right: right != null && index == right,
              chosen: chosen == index,
              rightLabel: l10n.cardsRecognizeRightChoice,
              onTap: view.heard && chosen == null
                  ? () => controller.choose(index)
                  : null,
            ),
          if (chosen != null && right != null) ...[
            ReportOnLongPress(
              onReport: report,
              child: Text(
                chosen == right
                    ? l10n.cardsRecognizeRight(view.headword ?? '')
                    : l10n.cardsRecognizeHeard(view.headword ?? ''),
                style: theme.textTheme.titleMedium,
              ),
            ),
            FilledButton(
              onPressed: () => unawaited(controller.next()),
              child: Text(l10n.cardsNext),
            ),
          ],
        ],
      ),
    );
  }
}

/// A meaning to choose; after the choice the right one carries a check.
class _Choice extends StatelessWidget {
  const new({
    required this.text,
    required this.right,
    required this.chosen,
    required this.rightLabel,
    required this.onTap,
  });

  final String text;
  final bool right;
  final bool chosen;

  /// What a screen reader says for the check.
  final String rightLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        backgroundColor: right ? theme.colorScheme.tertiaryContainer : null,
        foregroundColor: right ? theme.colorScheme.onTertiaryContainer : null,
        side: chosen
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : null,
      ),
      child: Row(
        spacing: 8,
        children: [
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
          if (right) Icon(Icons.check, semanticLabel: rightLabel),
        ],
      ),
    );
  }
}
