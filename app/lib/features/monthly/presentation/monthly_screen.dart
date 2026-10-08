import 'dart:async';

import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/features/monthly/application/monthly_controller.dart';
import 'package:dilbaz_app/features/monthly/application/monthly_state.dart';
import 'package:dilbaz_app/features/monthly/presentation/monthly_report_page.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_app/features/speaking/presentation/views/task_card_page.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The monthly speaking test (A23, docs/06 §3), or the placement test's
/// baseline recording ([baseline], §2 part 4). Leaving needs no
/// confirmation: what was recorded is kept (I-14).
class MonthlyScreen extends ConsumerWidget {
  const new({this.baseline = false, super.key});

  final bool baseline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final test = monthlyTestControllerProvider(baseline: baseline);
    final state = ref.watch(test);
    final controller = ref.read(test.notifier);

    Future<void> leave() async {
      await controller.leave();
      if (context.mounted && context.canPop()) context.pop();
    }

    void close() => unawaited(leave());

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(baseline ? l10n.monthlyBaselineTitle : l10n.monthlyTitle),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.monthlyLeave,
            onPressed: close,
          ),
        ),
        body: SafeArea(
          child: switch (state) {
            AsyncData(:final value) => switch (value) {
              MonthlyUnavailable() => _Page(
                content: [Text(l10n.monthlyUnavailable)],
                actions: [_Close(onClose: close)],
              ),
              MonthlyNeedsConsent() => _Page(
                content: [Text(l10n.speakingNeedsConsent)],
                actions: [_Close(onClose: close)],
              ),
              MonthlyIntro(:final tasks, :final limit) => _Page(
                content: [
                  Text(
                    baseline
                        ? l10n.monthlyBaselineIntro
                        : l10n.monthlyIntro(tasks, limit.inMinutes),
                  ),
                  Text(l10n.monthlyIntroPlace),
                ],
                actions: [
                  FilledButton(
                    onPressed: controller.begin,
                    child: Text(l10n.monthlyBegin),
                  ),
                ],
              ),
              MonthlyMicCheck(:final listening) => _Page(
                content: [
                  Text(l10n.monthlyMicCheck),
                  if (listening) const _LevelMeter(),
                ],
                actions: [
                  if (!listening)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(controller.checkMicrophone()),
                      icon: const Icon(Icons.mic),
                      label: Text(l10n.monthlyMicTry),
                    ),
                  FilledButton(
                    onPressed: () => unawaited(controller.microphoneOk()),
                    child: Text(l10n.monthlyMicOk),
                  ),
                ],
              ),
              MonthlyTask(:final step) => TaskCardPage(
                task: step.task,
                recording: step.recording,
                onStart: () => unawaited(controller.startRecording()),
                onStop: () => unawaited(controller.stopRecording()),
                header: [
                  Text(
                    l10n.monthlyTaskNumber(step.number, step.total),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  if (step.anchor) Text(l10n.monthlyAnchorNote),
                ],
              ),
              MonthlyFailed(:final failure) => _Page(
                content: [
                  Text(switch (failure) {
                    SpeakingFailure.permission => l10n.speakingFailedPermission,
                    SpeakingFailure.silent => l10n.speakingFailedSilent,
                    _ => l10n.speakingFailedMicrophone,
                  }),
                ],
                actions: [
                  if (failure != SpeakingFailure.permission)
                    FilledButton(
                      onPressed: controller.tryAgain,
                      child: Text(l10n.speakingRecordAgain),
                    ),
                  _Close(onClose: close),
                ],
              ),
              MonthlyFinishing() => _Page(
                content: [
                  const Center(child: CircularProgressIndicator()),
                  Text(l10n.monthlyFinishing, textAlign: TextAlign.center),
                ],
              ),
              MonthlyReport(:final tasks) => MonthlyReportPage(
                baseline: baseline,
                tasks: tasks,
                onClose: close,
              ),
            },
            AsyncError() => _Page(
              content: [Text(l10n.monthlyUnavailable)],
              actions: [_Close(onClose: close)],
            ),
            AsyncLoading() => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const new({required this.content, this.actions = const []});

  final List<Widget> content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: DefaultTextStyle.merge(
      style: Theme.of(context).textTheme.bodyLarge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 24,
        children: [...content, ...actions],
      ),
    ),
  );
}

class _Close extends StatelessWidget {
  const new({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: onClose, child: Text(context.l10n.cardsClose));
}

class _LevelMeter extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(answerLevelProvider).value ?? 0;
    return ExcludeSemantics(
      child: LinearProgressIndicator(value: level, minHeight: 8),
    );
  }
}
