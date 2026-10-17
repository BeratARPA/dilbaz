import 'dart:math';

import 'package:dilbaz_app/features/week/application/week_summary.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The week summary (docs/09 §5.13): what was done this week or last, in
/// counts and minutes; only what was done is listed, no percentage and
/// nothing about what was not (I-04, I-12).
class WeekScreen extends ConsumerStatefulWidget {
  const new({this.last = false, super.key});

  /// Opens on last week.
  final bool last;

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  late bool _last = widget.last;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final summary = ref.watch(weekSummaryProvider(last: _last));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.weekTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(l10n.weekThis)),
                  ButtonSegment(value: true, label: Text(l10n.weekLast)),
                ],
                selected: {_last},
                onSelectionChanged: (chosen) =>
                    setState(() => _last = chosen.single),
              ),
              switch (summary) {
                AsyncData(value: final week?) => _Week(week: week),
                AsyncData() || AsyncError() => Text(l10n.sectionInPreparation),
                AsyncLoading() => const Center(
                  child: CircularProgressIndicator(),
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

/// Minutes as the learner reads them: rounded, at least one.
int _minutes(Duration time) => max(1, (time.inSeconds / 60).round());

class _Week extends StatelessWidget {
  const new({required this.week});

  final WeekSummary week;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    final a = week.activity;
    final total = a.time.values.fold(Duration.zero, (sum, t) => sum + t);
    final strands = [
      for (final (strand, label) in [
        (Strand.language, l10n.weekStrandLanguage),
        (Strand.output, l10n.weekStrandOutput),
        (Strand.fluency, l10n.weekStrandFluency),
        (Strand.input, l10n.weekStrandInput),
      ])
        if (a.time[strand] case final time? when time > Duration.zero)
          label(_minutes(time)),
    ];
    final done = <(IconData, String)>[
      if (a.cardReviews > 0 || a.newItems > 0)
        (Icons.style_outlined, l10n.weekCards(a.cardReviews, a.newItems)),
      if (a.speakingTasks > 0)
        (Icons.mic_none, l10n.weekSpeakingTasks(a.speakingTasks)),
      if (a.speaking > Duration.zero)
        (Icons.graphic_eq, l10n.weekSpoken(_minutes(a.speaking))),
      if (a.monthly) (Icons.event_available_outlined, l10n.weekMonthly),
      if (a.fluency > 0) (Icons.timer_outlined, l10n.weekFluency(a.fluency)),
      if (a.dictation > 0) (Icons.hearing, l10n.weekDictation(a.dictation)),
      if (a.shadowing > 0)
        (Icons.record_voice_over_outlined, l10n.weekShadowing(a.shadowing)),
      if (a.captures > 0)
        (Icons.add_comment_outlined, l10n.weekCaptures(a.captures)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Text(
          l10n.weekRange(
            dates.formatShortMonthDay(week.from),
            dates.formatShortMonthDay(week.to),
          ),
          style: theme.textTheme.labelLarge,
        ),
        if (a.days.isEmpty && done.isEmpty)
          Text(l10n.weekNothing, style: theme.textTheme.bodyLarge)
        else ...[
          Text(
            l10n.weekDays(a.days.length, week.weeklyGoal),
            style: theme.textTheme.headlineSmall,
          ),
          if (total > Duration.zero) ...[
            Text(
              l10n.weekTime(_minutes(total)),
              style: theme.textTheme.titleMedium,
            ),
            if (strands.isNotEmpty) Text(strands.join(' · ')),
          ],
          for (final (icon, text) in done)
            Row(
              spacing: 12,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
              ],
            ),
        ],
      ],
    );
  }
}
