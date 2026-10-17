import 'dart:async';

import 'package:dilbaz_app/features/speaking/application/speaking_controller.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_app/features/speaking/presentation/views/feedback_page.dart';
import 'package:dilbaz_app/features/speaking/presentation/views/task_card_page.dart';
import 'package:dilbaz_app/features/speaking/presentation/views/task_choice_page.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A speaking task over the tabs (A11, docs/09 §5.6). Leaving needs no
/// confirmation: what was recorded is kept, nothing is owed (I-14).
class SpeakingScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(speakingControllerProvider);
    final controller = ref.read(speakingControllerProvider.notifier);

    Future<void> leave() async {
      await controller.leave();
      if (context.mounted && context.canPop()) context.pop();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.speakingTitle),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.speakingLeave,
            onPressed: () => unawaited(leave()),
          ),
        ),
        body: SafeArea(
          child: switch (state) {
            AsyncData(:final value) => switch (value) {
              SpeakingUnavailable() => _Note(
                text: l10n.speakingUnavailable,
                onClose: () => unawaited(leave()),
              ),
              SpeakingNeedsConsent() => _Note(
                text: l10n.speakingNeedsConsent,
                onClose: () => unawaited(leave()),
              ),
              SpeakingChoosing(:final suggested, :final others, :final ready) =>
                TaskChoicePage(
                  suggested: suggested,
                  others: others,
                  onChoose: controller.choose,
                  ready: ready,
                  onOpen: (id) => unawaited(controller.openRecording(id)),
                ),
              SpeakingPreparing(:final task) => TaskCardPage(
                task: task,
                recording: false,
                onStart: () => unawaited(controller.startRecording()),
                onStop: () {},
                onOtherTask: controller.chooseAgain,
              ),
              SpeakingRecording(:final task) => TaskCardPage(
                task: task,
                recording: true,
                onStart: () {},
                onStop: () => unawaited(controller.stopRecording()),
              ),
              SpeakingProcessing(:final step) => _Processing(step: step),
              SpeakingFailed(:final failure, :final canRetry) => _Failed(
                failure: failure,
                onClose: () => unawaited(leave()),
                onRetry: canRetry ? () => unawaited(controller.retry()) : null,
                onRecordAgain: failure == SpeakingFailure.permission
                    ? null
                    : controller.tryAgain,
              ),
              SpeakingFeedback(:final view) => FeedbackPage(view: view),
              SpeakingDone(:final cards) => _Done(
                cards: cards,
                onClose: () => unawaited(leave()),
              ),
            },
            AsyncError() => _Note(
              text: l10n.speakingUnavailable,
              onClose: () => unawaited(leave()),
            ),
            AsyncLoading() => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _Processing extends StatelessWidget {
  const new({required this.step});

  final ProcessingStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 24,
          children: [
            const CircularProgressIndicator(),
            Text(
              switch (step) {
                ProcessingStep.transcribing => l10n.speakingTranscribing,
                ProcessingStep.marking => l10n.speakingMarking,
              },
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const new({
    required this.failure,
    required this.onClose,
    this.onRetry,
    this.onRecordAgain,
  });

  final SpeakingFailure failure;
  final VoidCallback onClose;
  final VoidCallback? onRetry;
  final VoidCallback? onRecordAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Note(
      text: switch (failure) {
        SpeakingFailure.permission => l10n.speakingFailedPermission,
        SpeakingFailure.microphone => l10n.speakingFailedMicrophone,
        SpeakingFailure.silent => l10n.speakingFailedSilent,
        SpeakingFailure.network => l10n.speakingFailedNetwork,
        SpeakingFailure.speech => l10n.speakingFailedSpeech,
      },
      onClose: onClose,
      actions: [
        if (onRetry case final retry?)
          FilledButton(onPressed: retry, child: Text(l10n.speakingRetry)),
        if (onRecordAgain case final again?)
          OutlinedButton(
            onPressed: again,
            child: Text(l10n.speakingRecordAgain),
          ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const new({required this.cards, required this.onClose});

  final int cards;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Note(
      title: l10n.speakingDoneTitle,
      text: l10n.speakingDoneCards(cards),
      onClose: onClose,
    );
  }
}

class _Note extends StatelessWidget {
  const new({
    required this.text,
    required this.onClose,
    this.title,
    this.actions = const [],
  });

  final String? title;
  final String text;
  final VoidCallback onClose;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 24,
          children: [
            if (title case final title?)
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            ...actions,
            TextButton(
              onPressed: onClose,
              child: Text(context.l10n.cardsClose),
            ),
          ],
        ),
      ),
    );
  }
}
