import 'dart:async';

import 'package:dilbaz_app/app/theme/feedback_colors.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/cards/application/card_session_controller.dart';
import 'package:dilbaz_app/features/cards/application/card_session_state.dart';
import 'package:dilbaz_app/features/cards/presentation/hint_text.dart';
import 'package:dilbaz_app/features/cards/presentation/views/hold_to_speak_button.dart';
import 'package:dilbaz_app/l10n/audio_failure_text.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A card (A01, A02; docs/09 §5.3): the prompt in the learner's language,
/// then listening → checking → the result, the hint ladder step by step,
/// and at the end the correct sentence to hear and say once.
class CardPage extends ConsumerStatefulWidget {
  const new({required this.session, required this.view, super.key});

  final CardSessionControllerProvider session;
  final CardView view;

  @override
  ConsumerState<CardPage> createState() => _CardPageState();
}

class _CardPageState extends ConsumerState<CardPage> {
  final _answer = TextEditingController();
  final _fix = TextEditingController();

  /// The field for typing over what was heard, or over an answer the LLM
  /// was not sure of.
  var _fixing = false;

  @override
  void didUpdateWidget(CardPage old) {
    super.didUpdateWidget(old);
    if (old.view.number != widget.view.number) {
      _answer.clear();
      _fix.clear();
      _fixing = false;
    }
    if (widget.view.phase is CardChecking) _fixing = false;
  }

  @override
  void dispose() {
    _answer.dispose();
    _fix.dispose();
    super.dispose();
  }

  CardSessionController get _controller => ref.read(widget.session.notifier);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final view = widget.view;
    final phase = view.phase;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Text(
            view.input == AnswerInput.speak
                ? l10n.cardsSayIt
                : l10n.cardsTypeIt,
            style: theme.textTheme.labelLarge,
          ),
          Semantics(
            header: true,
            child: Text(view.prompt, style: theme.textTheme.headlineSmall),
          ),
          if (view.contextNote case final note?)
            _Line(icon: Icons.chat_bubble_outline, text: note),
          if (phase is CardEnded)
            ..._ended(context, phase)
          else ...[
            if (view.last case final last?) _LastAnswer(last: last),
            if (view.offline case final failure?)
              _Line(icon: Icons.info_outline, text: _offline(l10n, failure)),
            for (final (index, hint) in view.hints.indexed)
              _HintTile(number: index + 1, text: hintText(l10n, hint)),
            if (view.canHint || view.canReveal)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (view.canHint)
                    OutlinedButton.icon(
                      onPressed: _controller.nextHint,
                      icon: const Icon(Icons.lightbulb_outline),
                      label: Text(l10n.cardsHint),
                    ),
                  if (view.canReveal)
                    OutlinedButton.icon(
                      onPressed: _controller.reveal,
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(l10n.cardsReveal),
                    ),
                ],
              ),
            ..._retype(context),
            ..._answering(context),
          ],
        ],
      ),
    );
  }

  static String _offline(AppLocalizations l10n, TutorFailure failure) =>
      switch (failure) {
        TutorFailure.network => l10n.cardsOfflineNetwork,
        TutorFailure.quota => l10n.cardsOfflineQuota,
        _ => l10n.cardsOfflineOther,
      };

  /// "Yanlış duyuldu": the field opens on request.
  List<Widget> _retype(BuildContext context) {
    final l10n = context.l10n;
    if (!widget.view.canRetype) return const [];
    if (!_fixing) {
      return [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _fixing = true),
            icon: const Icon(Icons.hearing_disabled_outlined),
            label: Text(l10n.cardsMisheard),
          ),
        ),
      ];
    }
    return _fixField(context, l10n.cardsMisheardLabel);
  }

  List<Widget> _fixField(BuildContext context, String label) {
    final l10n = context.l10n;
    void send() => unawaited(_controller.retype(_fix.text));
    return [
      _AnswerField(controller: _fix, label: label, onSubmitted: (_) => send()),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(onPressed: send, child: Text(l10n.cardsFixSave)),
      ),
    ];
  }

  /// How the answer is given, by phase.
  List<Widget> _answering(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final view = widget.view;
    switch (view.phase) {
      case CardChecking():
        return [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 16,
            children: [
              const CircularProgressIndicator(),
              Flexible(child: Text(l10n.cardsChecking)),
            ],
          ),
        ];
      case CardConfirming():
        return [
          Text(l10n.cardsDidYouMean, style: theme.textTheme.titleMedium),
          if (_fixing)
            ..._fixField(context, l10n.cardsFixLabel)
          else
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _fixing = true),
                  child: Text(l10n.cardsDidYouMeanFix),
                ),
                FilledButton(
                  onPressed: _controller.confirm,
                  child: Text(l10n.cardsDidYouMeanYes),
                ),
              ],
            ),
        ];
      case CardAsking() || CardListening() when view.input == AnswerInput.speak:
        return [
          _SpeakArea(
            key: const ValueKey('speak'),
            session: widget.session,
            view: view,
          ),
        ];
      case CardAsking():
        void send() => unawaited(_controller.submit(_answer.text));
        return [
          _AnswerField(
            controller: _answer,
            label: l10n.cardsAnswerLabel,
            onChanged: (_) => _controller.startTyping(),
            onSubmitted: (_) => send(),
          ),
          Row(
            children: [
              if (view.canSpeak)
                Flexible(
                  child: TextButton.icon(
                    onPressed: _controller.switchInput,
                    icon: const Icon(Icons.mic_none),
                    label: Text(l10n.cardsSpeakInstead),
                  ),
                ),
              const Spacer(),
              FilledButton(onPressed: send, child: Text(l10n.cardsSend)),
            ],
          ),
        ];
      case CardListening() || CardEnded():
        return const [];
    }
  }

  List<Widget> _ended(BuildContext context, CardEnded phase) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<FeedbackColors>()!;
    final view = widget.view;
    final (icon, color, heading) = switch (phase.outcome) {
      Recalled() when phase.almost => (
        Icons.adjust,
        colors.nearMiss,
        l10n.cardsAlmost,
      ),
      Recalled() => (
        Icons.check_circle_outline,
        colors.correct,
        l10n.cardsCorrect,
      ),
      WithoutTarget() => (
        Icons.check_circle_outline,
        colors.correct,
        l10n.cardsWithoutTargetEnd,
      ),
      Undecided() => (
        Icons.hourglass_empty,
        theme.colorScheme.onSurfaceVariant,
        l10n.cardsUndecided,
      ),
      NotRecalled() => (
        Icons.menu_book_outlined,
        theme.colorScheme.onSurfaceVariant,
        l10n.cardsTheSentence,
      ),
    };
    return [
      Row(
        spacing: 12,
        children: [
          Icon(icon, color: color),
          Expanded(
            child: Text(
              heading,
              style: theme.textTheme.titleMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
      if (phase.correction case final correction?)
        Text(l10n.cardsCorrection(correction)),
      Text(phase.sentence, style: theme.textTheme.headlineSmall),
      if (view.hasClip)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: view.playing
                ? null
                : () => unawaited(_controller.play()),
            icon: const Icon(Icons.volume_up),
            label: Text(l10n.cardsListen),
          ),
        ),
      Text(l10n.cardsSayOnce, style: theme.textTheme.bodyLarge),
      ..._retype(context),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => unawaited(_controller.next()),
          child: Text(l10n.cardsNext),
        ),
      ),
    ];
  }
}

/// The microphone, what it hears, and the way to type instead.
class _SpeakArea extends ConsumerWidget {
  const new({required this.session, required this.view, super.key});

  final CardSessionControllerProvider session;
  final CardView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(session.notifier);
    final listening = view.phase is CardListening;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Center(
          child: HoldToSpeakButton(
            listening: listening,
            onStart: () => unawaited(controller.startSpeaking()),
            onStop: () => unawaited(controller.stopSpeaking()),
          ),
        ),
        Text(
          listening ? l10n.cardsRecording : l10n.cardsHoldToSpeak,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (listening) const _LevelMeter(),
        if (view.speechFailure case final failure?)
          _Line(
            icon: Icons.info_outline,
            text: speechFailureText(l10n, failure),
          ),
        if (view.recordFailure case final failure?)
          _Line(
            icon: Icons.info_outline,
            text: recordFailureText(l10n, failure),
          ),
        if (!listening)
          Center(
            child: TextButton.icon(
              onPressed: controller.switchInput,
              icon: const Icon(Icons.keyboard_outlined),
              label: Text(l10n.cardsTypeInstead),
            ),
          ),
      ],
    );
  }
}

class _LevelMeter extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) => LinearProgressIndicator(
    value: ref.watch(answerLevelProvider).value ?? 0,
    minHeight: 8,
    semanticsLabel: context.l10n.microphoneCheckLevel,
  );
}

/// The latest answer with the errors marked, and what to do next.
class _LastAnswer extends StatelessWidget {
  const new({required this.last});

  final LastAnswer last;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<FeedbackColors>()!;
    final feedback = switch (last.feedback) {
      AnswerFeedback.tryAgain => l10n.cardsTryAgain,
      AnswerFeedback.withoutTarget => l10n.cardsWithoutTarget,
      AnswerFeedback.unheard => l10n.cardsUnheard,
      null => null,
    };
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(
              last.heard ? l10n.cardsHeard : l10n.cardsYourAnswer,
              style: theme.textTheme.labelLarge,
            ),
            Text.rich(
              TextSpan(
                children: _marked(last.text, last.spans, colors.errorHighlight),
              ),
              style: theme.textTheme.titleLarge,
            ),
            if (feedback != null)
              Text(
                feedback,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: last.feedback == AnswerFeedback.withoutTarget
                      ? colors.correct
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// [text] with the error [spans] on a soft background (docs/09 §3).
  static List<InlineSpan> _marked(
    String text,
    List<ErrorSpan> spans,
    Color highlight,
  ) {
    final parts = <InlineSpan>[];
    var at = 0;
    for (final span in spans) {
      if (span.start < at || span.end > text.length) continue;
      parts
        ..add(TextSpan(text: text.substring(at, span.start)))
        ..add(
          TextSpan(
            text: text.substring(span.start, span.end),
            style: TextStyle(backgroundColor: highlight),
          ),
        );
      at = span.end;
    }
    parts.add(TextSpan(text: text.substring(at)));
    return parts;
  }
}

/// One hint of the ladder.
class _HintTile extends StatelessWidget {
  const new({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Icon(Icons.lightbulb_outline, color: theme.colorScheme.primary),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.cardsHintNumber(number),
                style: theme.textTheme.labelMedium,
              ),
              Text(text, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}

/// A text field for English: nothing may "correct" it (A02).
class _AnswerField extends StatelessWidget {
  const new({
    required this.controller,
    required this.label,
    required this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autocorrect: false,
    enableSuggestions: false,
    maxLength: 200,
    textCapitalization: TextCapitalization.sentences,
    textInputAction: TextInputAction.send,
    decoration: InputDecoration(labelText: label, counterText: ''),
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  );
}

class _Line extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Icon(
        icon,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      Expanded(child: Text(text)),
    ],
  );
}
