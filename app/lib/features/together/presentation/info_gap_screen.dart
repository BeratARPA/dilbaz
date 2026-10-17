import 'dart:async';

import 'package:dilbaz_app/features/cards/presentation/views/hold_to_speak_button.dart';
import 'package:dilbaz_app/features/together/application/info_gap_controller.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// An information gap task on one phone (A15, docs/09 §5.9): the task, the
/// learner's own role only, push to talk, the answer; then how it went and
/// the learner's own corrections. Never red, and nobody is ranked (I-12).
class InfoGapScreen extends ConsumerWidget {
  const new({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final provider = infoGapControllerProvider(sessionId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    Future<void> leave() async {
      await controller.cancel();
      if (context.mounted && context.canPop()) context.pop();
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gapTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: switch (state) {
            AsyncData(value: InfoGapInvited(:final task)) => _Page(
              children: [
                Text(task.title, style: Theme.of(context).textTheme.titleLarge),
                Text(task.prompt),
                FilledButton(
                  onPressed: () => unawaited(controller.join()),
                  child: Text(l10n.gapJoin),
                ),
                TextButton(
                  onPressed: () => unawaited(leave()),
                  child: Text(l10n.togetherNotNow),
                ),
              ],
            ),
            AsyncData(value: InfoGapWaiting(:final task)) => _Page(
              children: [
                Text(task.title, style: Theme.of(context).textTheme.titleLarge),
                // Waiting may be long: a still sign, not a spinner.
                const Icon(Icons.hourglass_empty, size: 40),
                Text(l10n.gapWaiting, textAlign: TextAlign.center),
                TextButton(
                  onPressed: () => unawaited(leave()),
                  child: Text(l10n.togetherCancel),
                ),
              ],
            ),
            AsyncData(value: final InfoGapPlaying playing) => _Playing(
              state: playing,
              controller: controller,
            ),
            AsyncData(
              value: InfoGapDone(:final task, :final check, :final feedback),
            ) =>
              _Page(
                children: [
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    check.solved
                        ? l10n.gapSolved
                        : l10n.gapFound(check.found, check.total),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(l10n.gapFeedbackTitle),
                  switch (feedback) {
                    GapNothingSaid() => Text(l10n.gapNothingSaid),
                    GapMarking() => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    GapFeedbackUnavailable() => Text(l10n.gapFeedbackLater),
                    GapCorrections(:final corrections)
                        when corrections.isEmpty =>
                      Text(l10n.gapNoCorrections),
                    GapCorrections(:final corrections) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 8,
                      children: [
                        for (final correction in corrections)
                          Card.outlined(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 4,
                                children: [
                                  Text(l10n.gapYouSaid(correction.original)),
                                  Text(
                                    correction.corrected,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  },
                  FilledButton(
                    onPressed: () => context.pop(),
                    child: Text(l10n.cardsClose),
                  ),
                ],
              ),
            AsyncData(value: InfoGapCancelled()) => _Page(
              children: [
                Text(l10n.gapCancelled),
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

class _Playing extends StatelessWidget {
  const new({required this.state, required this.controller});

  final InfoGapPlaying state;
  final InfoGapController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final mine = state.mine;
    final differences = mine.options.isEmpty && state.chooses;
    return _Page(
      children: [
        Text(state.task.title, style: theme.textTheme.titleLarge),
        Text(state.task.prompt),
        Text(mine.instruction, style: theme.textTheme.titleMedium),
        if (differences)
          for (final (i, line) in mine.lines.indexed)
            CheckboxListTile(
              value: state.marked.contains(i),
              onChanged: state.answered ? null : (_) => controller.toggle(i),
              title: Text(line),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            )
        else
          for (final line in mine.lines)
            Text(line, style: theme.textTheme.bodyLarge),
        if (mine.options.isNotEmpty)
          RadioGroup<String>(
            groupValue: state.chosen,
            onChanged: (id) {
              if (id != null && !state.answered) controller.choose(id);
            },
            child: Column(
              children: [
                for (final option in mine.options)
                  RadioListTile<String>(
                    value: option.id,
                    enabled: !state.answered,
                    title: Text(option.text),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        Center(
          child: HoldToSpeakButton(
            listening: state.recording,
            onStart: () => unawaited(controller.startSpeaking()),
            onStop: () => unawaited(controller.stopSpeaking()),
          ),
        ),
        Text(l10n.gapPushToTalk(state.said), textAlign: TextAlign.center),
        if (state.failed) Text(l10n.togetherFailed),
        if (state.answered)
          Text(l10n.gapAnswered)
        else
          FilledButton(
            onPressed: state.chooses && !differences && state.chosen == null
                ? null
                : () => unawaited(controller.submit()),
            child: Text(state.chooses ? l10n.gapSubmit : l10n.gapDoneAsked),
          ),
      ],
    );
  }
}

class _Page extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: Theme.of(context).textTheme.bodyLarge,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: children,
    ),
  );
}
