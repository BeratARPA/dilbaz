import 'dart:async';

import 'package:dilbaz_app/features/speaking/application/speaking_controller.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_app/features/speaking/presentation/views/correction_card.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The feedback of a recording (docs/03 A11 step 4, docs/09 §5.6): how
/// long and how much was said, what went well, then the corrections one by
/// one. No grade (I-04, I-12).
class FeedbackPage extends ConsumerWidget {
  const new({required this.view, super.key});

  final FeedbackView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(speakingControllerProvider.notifier);
    final corrections = view.corrections;
    final practised = view.current >= corrections.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Text(
            l10n.speakingStats(
              view.spoken.inMinutes,
              view.spoken.inSeconds % 60,
              view.words,
            ),
            style: theme.textTheme.titleMedium,
          ),
          ExpansionTile(
            title: Text(l10n.cardsHeard),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(view.transcript)],
          ),
          if (view.strengths.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text(l10n.speakingStrengths, style: theme.textTheme.titleSmall),
                for (final strength in view.strengths) Text(strength),
              ],
            ),
          if (view.waiting != null)
            Text(l10n.speakingWaiting, style: theme.textTheme.bodyMedium)
          else if (corrections.isEmpty)
            Text(l10n.speakingNoCorrections),
          if (corrections.isNotEmpty && !practised) ...[
            Text(
              l10n.speakingCorrectionNumber(
                view.current + 1,
                corrections.length,
              ),
              style: theme.textTheme.titleSmall,
            ),
            CorrectionCard(
              correction: corrections[view.current],
              typed: view.typed,
              last: view.current == corrections.length - 1,
            ),
          ],
          if (practised || corrections.isEmpty) ...[
            FilledButton(
              onPressed: () => unawaited(controller.finish()),
              child: Text(l10n.speakingFinish),
            ),
            OutlinedButton(
              onPressed: () => unawaited(controller.redo()),
              child: Text(l10n.speakingRedo),
            ),
          ],
        ],
      ),
    );
  }
}
