import 'dart:async';

import 'package:dilbaz_app/features/cards/presentation/hint_text.dart';
import 'package:dilbaz_app/features/cards/presentation/views/hold_to_speak_button.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_controller.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One correction to say again (docs/03 A11 4b): the learner's sentence,
/// then the hint ladder after each miss (I-02). The corrected sentence
/// shows once it is said right or asked for after a try (I-01).
class CorrectionCard extends ConsumerStatefulWidget {
  const new({
    required this.correction,
    required this.typed,
    required this.last,
    super.key,
  });

  final CorrectionView correction;

  /// Answers are typed (silent mode).
  final bool typed;

  /// The last correction: after it the feedback page goes on.
  final bool last;

  @override
  ConsumerState<CorrectionCard> createState() => _CorrectionCardState();
}

class _CorrectionCardState extends ConsumerState<CorrectionCard> {
  final _text = TextEditingController();

  @override
  void didUpdateWidget(CorrectionCard old) {
    super.didUpdateWidget(old);
    if (old.correction.original != widget.correction.original) _text.clear();
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
    final controller = ref.read(speakingControllerProvider.notifier);
    final correction = widget.correction;
    final phase = correction.phase;
    final ended =
        phase == CorrectionPhase.recalled || phase == CorrectionPhase.shown;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(l10n.speakingYourSentence, style: theme.textTheme.labelLarge),
            Text(correction.original, style: theme.textTheme.bodyLarge),
            if (!ended)
              Text(
                widget.typed
                    ? l10n.speakingTypeCorrected
                    : l10n.speakingSayCorrected,
                style: theme.textTheme.titleSmall,
              ),
            if (correction.last case final last? when !ended) ...[
              Text('${l10n.cardsHeard}: $last'),
              if (correction.hints.isNotEmpty) Text(l10n.cardsTryAgain),
            ],
            for (final (i, hint) in correction.hints.indexed)
              Text('${l10n.cardsHintNumber(i + 1)}: ${hintText(l10n, hint)}'),
            if (ended) ...[
              Text(
                phase == CorrectionPhase.recalled
                    ? l10n.cardsCorrect
                    : l10n.cardsTheSentence,
                style: theme.textTheme.titleSmall,
              ),
              if (correction.corrected case final corrected?)
                Text(corrected, style: theme.textTheme.titleMedium),
              if (!widget.last)
                FilledButton(
                  onPressed: controller.nextCorrection,
                  child: Text(l10n.speakingNext),
                )
              else
                FilledButton(
                  onPressed: controller.nextCorrection,
                  child: Text(l10n.cardsNext),
                ),
            ] else if (phase == CorrectionPhase.checking)
              Text(l10n.cardsChecking, textAlign: TextAlign.center)
            else if (widget.typed) ...[
              TextField(
                controller: _text,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: l10n.cardsAnswerLabel),
              ),
              FilledButton(
                onPressed: () => controller.submit(_text.text),
                child: Text(l10n.cardsSend),
              ),
            ] else
              Center(
                child: HoldToSpeakButton(
                  listening: phase == CorrectionPhase.listening,
                  onStart: () => unawaited(controller.startSaying()),
                  onStop: () => unawaited(controller.stopSaying()),
                ),
              ),
            if (!ended && phase == CorrectionPhase.asking)
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (correction.canHint)
                    TextButton(
                      onPressed: controller.nextHint,
                      child: Text(l10n.cardsHint),
                    ),
                  if (correction.canReveal)
                    TextButton(
                      onPressed: controller.reveal,
                      child: Text(l10n.cardsReveal),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
