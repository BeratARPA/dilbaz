import 'dart:async';

import 'package:dilbaz_app/features/shadowing/application/shadowing_controller.dart';
import 'package:dilbaz_app/features/shadowing/application/shadowing_state.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Shadowing over the tabs (A07): hear a sentence, say it the same way, see
/// at most two sounds to work on. No score, never red (I-04, I-12).
/// Leaving needs no confirmation: what was said is kept (I-14).
class ShadowingScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(shadowingControllerProvider);
    final controller = ref.read(shadowingControllerProvider.notifier);

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
          title: Text(l10n.shadowingTitle),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.shadowingLeave,
            onPressed: close,
          ),
        ),
        body: SafeArea(
          child: switch (state) {
            AsyncData(:final value) => switch (value) {
              ShadowingUnavailable() => _Page(
                content: [Text(l10n.speakingUnavailable)],
                actions: [_Close(onClose: close)],
              ),
              ShadowingNeedsConsent() => _Page(
                content: [Text(l10n.shadowingNeedsConsent)],
                actions: [_Close(onClose: close)],
              ),
              ShadowingNothingToSay() => _Page(
                content: [Text(l10n.shadowingNothingToSay)],
                actions: [_Close(onClose: close)],
              ),
              final ShadowingSentence sentence => _Sentence(state: sentence),
              ShadowingChecking() => _Page(
                content: [
                  const Center(child: CircularProgressIndicator()),
                  Text(l10n.shadowingChecking, textAlign: TextAlign.center),
                ],
              ),
              final ShadowingResult result => _Result(state: result),
              ShadowingDone(:final sentences, :final shown, :final about) =>
                _Page(
                  content: [
                    Text(
                      l10n.shadowingDoneTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(l10n.shadowingDoneSaid(sentences)),
                    if (shown.isNotEmpty) ...[
                      Text(l10n.shadowingDoneShown),
                      for (final tag in shown.keys) Text('• ${about[tag]}'),
                    ],
                    Text(l10n.shadowingDoneNote),
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

class _Sentence extends ConsumerWidget {
  const new({required this.state});

  final ShadowingSentence state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(shadowingControllerProvider.notifier);
    return _Page(
      content: [
        Text(
          l10n.shadowingSentenceOf(state.number, state.total),
          style: theme.textTheme.labelLarge,
        ),
        Text(state.again ? l10n.shadowingAgainIntro : l10n.shadowingIntro),
        // The sentence is read along: shadowing is not a listening test.
        Text(state.text, style: theme.textTheme.titleMedium),
        FilledButton.tonalIcon(
          onPressed: state.playing || state.recording
              ? null
              : () => unawaited(controller.listen()),
          icon: Icon(state.heard ? Icons.replay : Icons.volume_up),
          label: Text(
            state.heard ? l10n.shadowingListenAgain : l10n.shadowingListen,
          ),
        ),
        if (state.audioFailure != null) _Note(text: l10n.shadowingAudioFailure),
        if (state.failure case final failure?)
          _Note(
            text: switch (failure) {
              SpeakingFailure.permission => l10n.speakingFailedPermission,
              SpeakingFailure.silent => l10n.speakingFailedSilent,
              _ => l10n.speakingFailedMicrophone,
            },
          ),
        if (state.recording) Text(l10n.shadowingRecording),
        if (!state.heard) Text(l10n.shadowingListenFirst),
      ],
      actions: [
        if (state.recording)
          FilledButton.icon(
            onPressed: () => unawaited(controller.stop()),
            icon: const Icon(Icons.stop),
            label: Text(l10n.shadowingStop),
          )
        else
          FilledButton.icon(
            onPressed: state.heard && !state.playing
                ? () => unawaited(controller.record())
                : null,
            icon: const Icon(Icons.mic),
            label: Text(l10n.shadowingRecord),
          ),
      ],
    );
  }
}

class _Result extends ConsumerWidget {
  const new({required this.state});

  final ShadowingResult state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(shadowingControllerProvider.notifier);
    final marks = state.marks;
    final unclear = {
      for (final issue in state.issues) issue.word.toLowerCase(),
    };
    bool off(int i) =>
        marks != null &&
        marks[i] != DictationMark.heard &&
        marks[i] != DictationMark.slip;
    final notRecognized = [
      for (final (i, word) in state.words.indexed)
        if (off(i)) word,
    ];
    final last = state.number == state.total;
    return _Page(
      content: [
        Text(
          l10n.shadowingSentenceOf(state.number, state.total),
          style: theme.textTheme.labelLarge,
        ),
        Text(l10n.shadowingWords, style: theme.textTheme.titleSmall),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final (i, word) in state.words.indexed)
              _Word(
                word: word,
                marked: off(i) || unclear.contains(_bare(word)),
              ),
          ],
        ),
        if (marks == null)
          Text(l10n.shadowingNoRecognition)
        else if (notRecognized.isEmpty)
          Text(l10n.shadowingAllRecognized)
        else
          Text(l10n.shadowingNotRecognized(notRecognized.join(', '))),
        switch (state.judgement) {
          PronJudgement.heard when state.issues.isEmpty => Text(
            l10n.shadowingNoIssue,
          ),
          PronJudgement.heard => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              Text(
                l10n.shadowingIssuesTitle,
                style: theme.textTheme.titleSmall,
              ),
              for (final issue in state.issues)
                Card.outlined(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 4,
                      children: [
                        Text(
                          l10n.shadowingIssue(issue.word, issue.heard),
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(issue.about),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          PronJudgement.uncertain => _Note(text: l10n.shadowingUncertain),
          PronJudgement.notHeard => _Note(text: l10n.shadowingNotHeard),
        },
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (state.canHearSelf)
              OutlinedButton.icon(
                onPressed: state.playing
                    ? null
                    : () => unawaited(controller.hearSelf()),
                icon: const Icon(Icons.person_outline),
                label: Text(l10n.shadowingHearSelf),
              ),
            OutlinedButton.icon(
              onPressed: state.playing
                  ? null
                  : () => unawaited(controller.hearModel()),
              icon: const Icon(Icons.volume_up),
              label: Text(l10n.shadowingHearModel),
            ),
          ],
        ),
      ],
      actions: [
        if (state.canTryAgain)
          OutlinedButton.icon(
            onPressed: () => unawaited(controller.tryAgain()),
            icon: const Icon(Icons.replay),
            label: Text(l10n.shadowingTryAgain),
          ),
        FilledButton(
          onPressed: () => unawaited(controller.next()),
          child: Text(last ? l10n.shadowingFinish : l10n.shadowingNext),
        ),
      ],
    );
  }

  static String _bare(String word) => word.toLowerCase().replaceAll(
    RegExp(r"^[^\p{L}\p{N}']+|[^\p{L}\p{N}']+$", unicode: true),
    '',
  );
}

/// A word of the sentence: as is, or marked to look at; never red (I-12).
class _Word extends StatelessWidget {
  const new({required this.word, required this.marked});

  final String word;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium;
    if (!marked) return Text(word, style: style);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          word,
          style: style?.copyWith(
            color: theme.colorScheme.onTertiaryContainer,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
      Expanded(child: Text(text)),
    ],
  );
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
        spacing: 16,
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
