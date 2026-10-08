import 'package:dilbaz_app/features/monthly/application/monthly_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// The monthly test's report (docs/06 §3.4, §6): each task's measures,
/// an anchor next to last month's, counts rather than percentages, and
/// what each measure is. No grade, no red, nothing called a failure.
class MonthlyReportPage extends StatelessWidget {
  const new({
    required this.baseline,
    required this.tasks,
    required this.onClose,
    super.key,
  });

  final bool baseline;
  final List<ReportTask> tasks;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Text(
            baseline ? l10n.monthlyBaselineTitle : l10n.monthlyReportTitle,
            style: theme.textTheme.titleLarge,
          ),
          Text(baseline ? l10n.monthlyBaselineDone : l10n.monthlyReportIntro),
          for (final task in tasks) _TaskCard(task: task),
          ExpansionTile(
            title: Text(l10n.monthlyWhatIsThis),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.monthlyExplainRate),
              const SizedBox(height: 8),
              Text(l10n.monthlyExplainPauses),
              const SizedBox(height: 8),
              Text(l10n.monthlyExplainErrorFree),
            ],
          ),
          FilledButton(onPressed: onClose, child: Text(l10n.cardsClose)),
        ],
      ),
    );
  }
}

/// A rate with one decimal, as Turkish writes it ("1,5").
String _decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',');

class _TaskCard extends StatelessWidget {
  const new({required this.task});

  final ReportTask task;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final spoken = task.spoken;
    final rate = task.speechRate;
    final pauses = task.longPausesPerMin;
    final clauses = task.clauses;
    final errorFree = task.errorFree;
    Widget previous(String value) =>
        Text(l10n.monthlyPrevious(value), style: theme.textTheme.bodySmall);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(task.title, style: theme.textTheme.titleMedium),
            if (task.anchor) Text(l10n.monthlyAnchorNote),
            if (spoken == null)
              Text(l10n.monthlyNotProcessed)
            else ...[
              Text(
                l10n.speakingStats(
                  spoken.inMinutes,
                  spoken.inSeconds % 60,
                  task.words ?? 0,
                ),
              ),
              if (rate != null) ...[
                Text(l10n.monthlySpeechRate(rate.round())),
                if (task.previousSpeechRate case final before?)
                  previous('${before.round()}'),
              ],
              if (pauses != null) ...[
                Text(l10n.monthlyLongPauses(_decimal(pauses))),
                if (task.previousLongPausesPerMin case final before?)
                  previous(_decimal(before)),
              ],
              if (clauses != null && errorFree != null) ...[
                Text(l10n.monthlyErrorFree(clauses, errorFree)),
                if ((task.previousClauses, task.previousErrorFree) case (
                  final int all,
                  final int clean,
                ))
                  previous('$clean / $all'),
              ] else
                Text(l10n.monthlyNotMarked),
            ],
          ],
        ),
      ),
    );
  }
}
