import 'dart:async';

import 'package:dilbaz_app/features/fluency/application/fluency_controller.dart';
import 'package:dilbaz_app/features/fluency/application/fluency_state.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_app/features/speaking/presentation/views/task_card_page.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 4/3/2 over the tabs (A12, docs/09 §5.7): a round counter, the measures
/// between rounds, the three rounds side by side at the end. Leaving needs
/// no confirmation: what was said is kept (I-14).
class FluencyScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(fluencyControllerProvider);
    final controller = ref.read(fluencyControllerProvider.notifier);

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
          title: Text(l10n.fluencyTitle),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.fluencyLeave,
            onPressed: close,
          ),
        ),
        body: SafeArea(
          child: switch (state) {
            AsyncData(:final value) => switch (value) {
              FluencyUnavailable() => _Page(
                content: [Text(l10n.speakingUnavailable)],
                actions: [_Close(onClose: close)],
              ),
              FluencyNeedsConsent() => _Page(
                content: [Text(l10n.speakingNeedsConsent)],
                actions: [_Close(onClose: close)],
              ),
              FluencyNoTopic() => _Page(
                content: [Text(l10n.fluencyNoTopic)],
                actions: [_Close(onClose: close)],
              ),
              FluencyChoosing(:final topics, :final rounds) => _Page(
                content: [
                  Text(
                    l10n.fluencyChooseTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    l10n.fluencyRoundsNote(
                      timeText(l10n, rounds[0]),
                      timeText(l10n, rounds[1]),
                      timeText(l10n, rounds[2]),
                    ),
                  ),
                  for (final topic in topics)
                    Card.outlined(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        title: Text(topic.title),
                        onTap: () => controller.choose(topic.key),
                      ),
                    ),
                ],
              ),
              FluencyRound(:final task, :final number, :final recording) =>
                TaskCardPage(
                  task: task,
                  recording: recording,
                  onStart: () => unawaited(controller.startRound()),
                  onStop: () => unawaited(controller.stopRound()),
                  header: [
                    Text(
                      l10n.fluencyRoundNumber(number),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(timeText(l10n, task.limit)),
                  ],
                ),
              FluencyChecking() => _Page(
                content: [
                  const Center(child: CircularProgressIndicator()),
                  Text(l10n.fluencyChecking, textAlign: TextAlign.center),
                ],
              ),
              FluencyFailed(:final failure) => _Page(
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
                      onPressed: controller.nextRound,
                      child: Text(l10n.speakingRecordAgain),
                    ),
                  _Close(onClose: close),
                ],
              ),
              FluencyBetween(:final results, :final next) => _Page(
                content: [
                  for (final result in results) _Result(result: result),
                  Text(l10n.fluencyNext(timeText(l10n, next))),
                ],
                actions: [
                  FilledButton(
                    onPressed: controller.nextRound,
                    child: Text(l10n.fluencyNextRound),
                  ),
                ],
              ),
              FluencyDone(:final results) => _Page(
                content: [
                  Text(
                    l10n.fluencyDoneTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  _Bars(results: results),
                  for (final result in results) _Result(result: result),
                  Text(l10n.fluencyDoneNote),
                ],
                actions: [_Close(onClose: close)],
              ),
            },
            AsyncError() => _Page(
              content: [Text(l10n.speakingUnavailable)],
              actions: [_Close(onClose: close)],
            ),
            AsyncLoading() => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

/// A round's time as said: "90 sn", "2 dk", "1,5 dk".
String timeText(AppLocalizations l10n, Duration time) {
  final seconds = time.inSeconds;
  if (seconds < 60 || seconds % 30 != 0) return l10n.fluencySeconds('$seconds');
  final minutes = seconds / 60;
  return l10n.fluencyMinutes(
    minutes == minutes.roundToDouble()
        ? '${minutes.round()}'
        : minutes.toStringAsFixed(1).replaceAll('.', ','),
  );
}

class _Result extends StatelessWidget {
  const new({required this.result});

  final RoundResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rate = result.speechRate;
    final pauses = result.longPausesPerMin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          l10n.fluencyRoundResult(result.number),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          rate == null || pauses == null
              ? l10n.fluencyNotMeasured
              : l10n.fluencyMeasures(
                  '${rate.round()}',
                  pauses.toStringAsFixed(1).replaceAll('.', ','),
                ),
        ),
      ],
    );
  }
}

/// Words a minute of the three rounds, as bars; the numbers are beside
/// them in the rows below, so the bars carry no meaning of their own.
class _Bars extends StatelessWidget {
  const new({required this.results});

  final List<RoundResult> results;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final rates = [for (final result in results) result.speechRate ?? 0];
    final top = rates.fold<double>(0, (a, b) => a > b ? a : b);
    if (top <= 0) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: 16,
          children: [
            for (final (i, rate) in rates.indexed)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 4,
                  children: [
                    Text('${rate.round()}', style: theme.textTheme.labelMedium),
                    Container(
                      height: 100 * rate / top,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Text(
                      l10n.fluencyRoundResult(results[i].number),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
          ],
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
