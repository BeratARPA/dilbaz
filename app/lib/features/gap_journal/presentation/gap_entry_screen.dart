import 'dart:async';

import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/features/gap_journal/application/gap_entry_controller.dart';
import 'package:dilbaz_app/features/gap_journal/presentation/gap_texts.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The suggestion of one capture (A19, docs/09 §5.5): the natural and the
/// simple English, the phrase to keep, and "add to cards".
class GapEntryScreen extends ConsumerWidget {
  const new({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(gapEntryControllerProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.gapEntryTitle)),
      body: SafeArea(
        child: switch (state) {
          AsyncData(:final value) => _Entry(id: id, state: value),
          AsyncError() => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l10n.gapEntryPending, textAlign: TextAlign.center),
            ),
          ),
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _Entry extends ConsumerWidget {
  const new({required this.id, required this.state});

  final String id;
  final GapEntryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(gapEntryControllerProvider(id).notifier);
    final entry = state.entry;
    final suggestion = entry.suggestion;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.gapEntryYouWanted, style: theme.textTheme.labelLarge),
          Text(entry.l1Text, style: theme.textTheme.titleMedium),
          Text(
            gapContextText(l10n, entry.context),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          if (suggestion == null)
            ..._waiting(context, controller)
          else ...[
            _Version(label: l10n.gapEntryNatural, text: suggestion.l2Natural),
            if (suggestion.l2Simple != suggestion.l2Natural)
              _Version(label: l10n.gapEntrySimple, text: suggestion.l2Simple),
            _Version(
              label: l10n.gapEntryChunk,
              text: l10n.gapEntryChunkLine(
                suggestion.keyChunk.text,
                suggestion.keyChunk.glossL1,
              ),
            ),
            if (suggestion.notesL1 case final notes?)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    Expanded(child: Text(notes)),
                  ],
                ),
              ),
            ..._decision(context, controller, suggestion),
          ],
        ],
      ),
    );
  }

  List<Widget> _waiting(BuildContext context, GapEntryController controller) {
    final l10n = context.l10n;
    if (state.asking) {
      return [
        Row(
          spacing: 16,
          children: [
            const CircularProgressIndicator(),
            Expanded(child: Text(l10n.gapEntryWaiting)),
          ],
        ),
      ];
    }
    return [
      Text(l10n.gapEntryPending),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () => unawaited(controller.retry()),
          child: Text(l10n.gapEntryRetry),
        ),
      ),
    ];
  }

  List<Widget> _decision(
    BuildContext context,
    GapEntryController controller,
    GapSuggestion suggestion,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (state.entry.status == GapStatus.carded) {
      return [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
            Expanded(child: Text(l10n.gapEntryCarded)),
          ],
        ),
      ];
    }
    final twoVersions = suggestion.l2Simple != suggestion.l2Natural;
    return [
      if (state.entry.status == GapStatus.dismissed) ...[
        Text(l10n.gapEntryDismissed),
        const SizedBox(height: 8),
      ],
      if (twoVersions) ...[
        Text(l10n.gapEntryCardWhich, style: theme.textTheme.titleSmall),
        RadioGroup<bool>(
          groupValue: state.natural,
          onChanged: (natural) {
            if (natural != null) controller.choose(natural: natural);
          },
          child: Column(
            children: [
              RadioListTile<bool>(
                value: false,
                title: Text(suggestion.l2Simple),
                subtitle: Text(l10n.gapEntrySimple),
              ),
              RadioListTile<bool>(
                value: true,
                title: Text(suggestion.l2Natural),
                subtitle: Text(l10n.gapEntryNatural),
              ),
            ],
          ),
        ),
      ],
      CheckboxListTile(
        value: state.withChunk,
        onChanged: (keep) => controller.keepChunk(keep: keep ?? false),
        title: Text(l10n.gapEntryWithChunk),
        subtitle: Text(suggestion.keyChunk.text),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          if (state.entry.status == GapStatus.fresh)
            TextButton(
              onPressed: state.saving
                  ? null
                  : () => unawaited(controller.dismiss()),
              child: Text(l10n.gapEntryDismiss),
            ),
          FilledButton(
            onPressed: state.saving
                ? null
                : () => unawaited(controller.addToCards()),
            child: Text(l10n.gapEntryAddToCards),
          ),
        ],
      ),
    ];
  }
}

class _Version extends StatelessWidget {
  const new({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          SelectableText(text, style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }
}
