import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/features/placement/application/placement_state.dart';
import 'package:dilbaz_app/features/placement/presentation/level_text.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// What the test found: where the curriculum starts, and each measured
/// skill as a level or a range. No score or grade (docs/06 §6, I-04).
class ReportView extends StatelessWidget {
  const new({required this.report, super.key});

  final PlacementReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final vocabulary = report.vocabulary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.placementResultTitle(report.start.code),
              style: theme.textTheme.headlineSmall,
            ),
          ),
          if (report.vocabularyLevel case final level?)
            _Skill(
              title: l10n.placementSkillVocabulary(levelText(l10n, level)),
              details: [
                if (vocabulary != null)
                  l10n.placementResultVocabulary(vocabulary),
                if (report.guesswork) l10n.placementResultGuesswork,
              ],
            ),
          if (report.grammarLevel case final level?)
            _Skill(title: l10n.placementSkillGrammar(levelText(l10n, level))),
          if (report.listeningLevel case final level?)
            _Skill(title: l10n.placementSkillListening(levelText(l10n, level))),
          Text(
            report.retake
                ? l10n.placementResultNoteRetake
                : l10n.placementResultNote,
            style: theme.textTheme.bodyMedium,
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            overflowAlignment: OverflowBarAlignment.end,
            children: [
              // The optional first recording, kept for before/after
              // listening (docs/06 §2 part 4).
              if (report.offerBaseline)
                TextButton(
                  onPressed: () => context.pushReplacement(AppRoutes.baseline),
                  child: Text(l10n.placementBaselineOffer),
                ),
              FilledButton(
                onPressed: () => context.pop(),
                child: Text(l10n.placementDone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Skill extends StatelessWidget {
  const new({required this.title, this.details = const []});

  final String title;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            for (final detail in details)
              Text(detail, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
