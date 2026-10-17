import 'dart:async';

import 'package:dilbaz_app/features/dictation_practice/application/dictation_practice_controller.dart';
import 'package:dilbaz_app/features/dictation_practice/application/dictation_practice_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Dictation over the tabs (A05): hear, write, see what was heard word by
/// word. Misses are marked by kind, never in red (I-12). Leaving needs no
/// confirmation: what was written is kept (I-14).
class DictationPracticeScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(dictationPracticeControllerProvider);
    final controller = ref.read(dictationPracticeControllerProvider.notifier);

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
          title: Text(l10n.dictationTitle),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.dictationLeave,
            onPressed: close,
          ),
        ),
        body: SafeArea(
          child: switch (state) {
            AsyncData(:final value) => switch (value) {
              DictationUnavailable() => _Page(
                content: [Text(l10n.speakingUnavailable)],
                actions: [_Close(onClose: close)],
              ),
              DictationNothingToHear() => _Page(
                content: [Text(l10n.dictationNothingToHear)],
                actions: [_Close(onClose: close)],
              ),
              final DictationListening listening => _Listening(
                state: listening,
              ),
              final DictationChecked checked => _Checked(state: checked),
              DictationDone(
                :final sentences,
                :final heardRight,
                :final misses,
              ) =>
                _Page(
                  content: [
                    Text(
                      l10n.dictationDoneTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(l10n.dictationDoneHeard(heardRight, sentences)),
                    if (misses[DictationMark.weakForm] case final n?)
                      Text(l10n.dictationDoneWeakForm(n)),
                    if (misses[DictationMark.ending] case final n?)
                      Text(l10n.dictationDoneEnding(n)),
                    if (misses[DictationMark.missed] case final n?)
                      Text(l10n.dictationDoneMissed(n)),
                    if (misses[DictationMark.changed] case final n?)
                      Text(l10n.dictationDoneChanged(n)),
                    Text(l10n.dictationDoneNote),
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

class _Listening extends ConsumerStatefulWidget {
  const new({required this.state});

  final DictationListening state;

  @override
  ConsumerState<_Listening> createState() => _ListeningState();
}

class _ListeningState extends ConsumerState<_Listening> {
  final _text = TextEditingController();

  @override
  void didUpdateWidget(_Listening old) {
    super.didUpdateWidget(old);
    if (old.state.number != widget.state.number ||
        old.state.slow != widget.state.slow) {
      _text.clear();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = widget.state;
    final controller = ref.read(dictationPracticeControllerProvider.notifier);
    void check() => controller.check(_text.text);
    return _Page(
      content: [
        Text(
          l10n.dictationSentenceOf(state.number, state.total),
          style: theme.textTheme.labelLarge,
        ),
        Text(state.slow ? l10n.dictationSlowIntro : l10n.dictationIntro),
        FilledButton.tonalIcon(
          onPressed: state.playing
              ? null
              : () => unawaited(controller.listen()),
          icon: Icon(state.heard ? Icons.replay : Icons.volume_up),
          label: Text(
            state.heard ? l10n.dictationListenAgain : l10n.dictationListen,
          ),
        ),
        if (state.failure != null)
          Row(
            spacing: 8,
            children: [
              Icon(Icons.info_outline, color: theme.colorScheme.primary),
              Expanded(child: Text(l10n.dictationAudioFailure)),
            ],
          ),
        TextField(
          controller: _text,
          enabled: state.heard,
          // English typed on any keyboard: nothing may "correct" it.
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: l10n.dictationWriteLabel),
          onSubmitted: state.heard ? (_) => check() : null,
        ),
      ],
      actions: [
        FilledButton(
          onPressed: state.heard ? check : null,
          child: Text(l10n.dictationCheck),
        ),
      ],
    );
  }
}

class _Checked extends ConsumerWidget {
  const new({required this.state});

  final DictationChecked state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(dictationPracticeControllerProvider.notifier);
    final result = state.result;
    List<String> wordsOf(DictationMark mark) => [
      for (final (i, word) in result.words.indexed)
        if (result.marks[i] == mark) word,
    ];
    final notes = [
      (wordsOf(DictationMark.weakForm), l10n.dictationMarkWeakForm),
      (wordsOf(DictationMark.ending), l10n.dictationMarkEnding),
      (wordsOf(DictationMark.missed), l10n.dictationMarkMissed),
      (wordsOf(DictationMark.changed), l10n.dictationMarkChanged),
      (result.extra, l10n.dictationMarkExtra),
      (wordsOf(DictationMark.slip), l10n.dictationMarkSlip),
    ];
    final last = state.number == state.total;
    return _Page(
      content: [
        Text(
          l10n.dictationSentenceOf(state.number, state.total),
          style: theme.textTheme.labelLarge,
        ),
        Text(l10n.dictationSentence, style: theme.textTheme.titleSmall),
        // The sentence, its misses underlined; the kinds are said below.
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final (i, word) in result.words.indexed)
              _Word(word: word, mark: result.marks[i]),
          ],
        ),
        Text(l10n.dictationYours, style: theme.textTheme.titleSmall),
        Text(result.typed),
        if (result.errors == 0) Text(l10n.dictationAllHeard),
        for (final (words, text) in notes)
          if (words.isNotEmpty) Text(text(words.join(', '))),
      ],
      actions: [
        if (state.canTryAgain)
          OutlinedButton.icon(
            onPressed: controller.tryAgainSlowly,
            icon: const Icon(Icons.slow_motion_video),
            label: Text(l10n.dictationTryAgainSlowly),
          ),
        FilledButton(
          onPressed: () => unawaited(controller.next()),
          child: Text(last ? l10n.dictationFinish : l10n.dictationNext),
        ),
      ],
    );
  }
}

/// A word of the sentence: as is when heard, marked when not.
class _Word extends StatelessWidget {
  const new({required this.word, required this.mark});

  final String word;
  final DictationMark mark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missed = mark != DictationMark.heard && mark != DictationMark.slip;
    final style = theme.textTheme.titleMedium;
    if (!missed) return Text(word, style: style);
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
