import 'dart:async';

import 'package:dilbaz_app/features/placement/application/placement_controller.dart';
import 'package:dilbaz_app/features/placement/application/placement_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One dictation sentence: play it, then write down what was heard. The
/// field opens once the sentence was heard.
class ListeningView extends ConsumerStatefulWidget {
  const new({required this.state, super.key});

  final PlacementListening state;

  @override
  ConsumerState<ListeningView> createState() => _ListeningViewState();
}

class _ListeningViewState extends ConsumerState<ListeningView> {
  final _text = TextEditingController();

  @override
  void didUpdateWidget(ListeningView old) {
    super.didUpdateWidget(old);
    // A new sentence starts with an empty field.
    if (old.state.number != widget.state.number) _text.clear();
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
    final controller = ref.read(placementControllerProvider.notifier);
    final state = widget.state;
    final canPlay = !state.playing && state.playsLeft > 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Text(
            l10n.placementSentenceOf(state.number, state.total),
            style: theme.textTheme.bodySmall,
          ),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
            ),
            onPressed: canPlay ? () => unawaited(controller.listen()) : null,
            icon: Icon(state.heard ? Icons.replay : Icons.volume_up),
            label: Text(
              state.heard ? l10n.placementListenAgain : l10n.placementListen,
            ),
          ),
          if (state.playing) const LinearProgressIndicator(),
          Text(
            l10n.placementPlaysLeft(state.playsLeft),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (state.failure != null) ...[
            Row(
              spacing: 8,
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.error),
                Expanded(child: Text(l10n.placementAudioFailure)),
              ],
            ),
            TextButton(
              onPressed: controller.skipDictation,
              child: Text(l10n.placementSkipDictation),
            ),
          ],
          TextField(
            controller: _text,
            enabled: state.heard,
            // English typed on any keyboard: nothing may "correct" it.
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.placementWriteLabel),
            onSubmitted: state.heard ? controller.write : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: state.heard
                  ? () => controller.write(_text.text)
                  : null,
              child: Text(l10n.placementContinue),
            ),
          ),
        ],
      ),
    );
  }
}
