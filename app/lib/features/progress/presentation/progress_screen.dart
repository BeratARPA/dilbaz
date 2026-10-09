import 'dart:async';

import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/features/progress/application/progress_controller.dart';
import 'package:dilbaz_app/features/progress/application/progress_view.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Progress tab (docs/09 §5.11, v1): evidence counts, the can-dos and the
/// monthly recordings to listen to side by side, with their trend. Counts,
/// never a made-up percentage (I-04); what each number is, on request.
/// Settings open from its top-right corner.
class ProgressScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final view = ref.watch(progressProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabProgress),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTitle,
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: view == null
          ? Center(child: Text(l10n.sectionInPreparation))
          : RefreshIndicator(
              onRefresh: () => ref.refresh(progressProvider.future),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                // The end scrolls clear of the "Söyleyemedim" button.
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 24,
                  children: [
                    _Evidence(view: view),
                    if (view.canDos.isNotEmpty) _CanDos(view: view),
                    _Monthly(view: view),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Evidence extends StatelessWidget {
  const new({required this.view});

  final ProgressView view;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final counts = view.counts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Text(l10n.progressEvidenceTitle, style: theme.textTheme.titleLarge),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, count) in [
              (l10n.progressKnown, counts.known),
              (l10n.progressRecallable, counts.recallable),
              (l10n.progressDurable, counts.durable),
              (l10n.progressUsed, counts.used),
            ])
              Card.outlined(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    children: [
                      Text('$count', style: theme.textTheme.headlineSmall),
                      Text(label),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (view.vocabulary case final words?)
          Text(l10n.progressVocabulary(words)),
        ExpansionTile(
          title: Text(l10n.progressWhatAreThese),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final text in [
              l10n.progressExplainKnown,
              l10n.progressExplainRecallable,
              l10n.progressExplainDurable,
              l10n.progressExplainUsed,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(text),
              ),
          ],
        ),
      ],
    );
  }
}

class _CanDos extends StatelessWidget {
  const new({required this.view});

  final ProgressView view;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Text(l10n.progressCanDoTitle, style: theme.textTheme.titleLarge),
        for (final canDo in view.canDos)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(canDo.summary),
              Text(switch (canDo.status) {
                CanDoStatus.established => l10n.progressCanDoEstablished,
                CanDoStatus.shown => l10n.progressCanDoShown,
                CanDoStatus.attempted => l10n.progressCanDoAttempted,
                CanDoStatus.none => l10n.progressCanDoNone,
              }, style: theme.textTheme.labelLarge),
              if (canDo.refresh)
                Text(
                  l10n.progressCanDoRefresh,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
      ],
    );
  }
}

class _Monthly extends ConsumerWidget {
  const new({required this.view});

  final ProgressView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final material = MaterialLocalizations.of(context);
    // Watched: it stays while a recording made elsewhere comes down.
    final fetching = ref.watch(recordingPlaybackProvider);
    final anchors = [
      for (final anchor in view.anchors)
        if (anchor.recordings.isNotEmpty || anchor.months.isNotEmpty) anchor,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Text(l10n.progressMonthlyTitle, style: theme.textTheme.titleLarge),
        if (anchors.isEmpty) Text(l10n.progressMonthlyEmpty),
        // The optional first recording (docs/06 §2 part 4).
        if (view.offerBaseline)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                await context.push(AppRoutes.baseline);
                if (context.mounted) ref.invalidate(progressProvider);
              },
              child: Text(l10n.progressBaselineOffer),
            ),
          ),
        for (final anchor in anchors)
          Card.outlined(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Text(anchor.title, style: theme.textTheme.titleMedium),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final recording in anchor.recordings)
                        OutlinedButton.icon(
                          onPressed: fetching != null
                              ? null
                              : () => unawaited(
                                  ref
                                      .read(recordingPlaybackProvider.notifier)
                                      .play(recording.path),
                                ),
                          icon: fetching == recording.path
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(
                            '${_momentText(context, recording.moment)} · '
                            '${material.formatShortDate(recording.day)}',
                          ),
                        ),
                    ],
                  ),
                  for (final month in anchor.months)
                    Text(_monthText(context, month)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _monthText(BuildContext context, MonthRow month) {
    final l10n = context.l10n;
    final rate = month.speechRate;
    final pauses = month.longPausesPerMin;
    final clauses = month.clauses;
    final errorFree = month.errorFree;
    final parts = [
      if (rate != null) l10n.progressRate(rate.round()),
      if (pauses != null)
        l10n.progressPauses(pauses.toStringAsFixed(1).replaceAll('.', ',')),
      if (clauses != null && errorFree != null)
        l10n.progressClauses(clauses, errorFree),
    ];
    final when = MaterialLocalizations.of(context).formatMonthYear(month.month);
    final measured = parts.isEmpty
        ? l10n.progressNotMeasured
        : parts.join(' · ');
    return '$when: $measured';
  }

  static String _momentText(BuildContext context, AnchorMoment moment) =>
      switch (moment) {
        AnchorMoment.first => context.l10n.progressListenFirst,
        AnchorMoment.previous => context.l10n.progressListenPrevious,
        AnchorMoment.latest => context.l10n.progressListenLatest,
      };
}
