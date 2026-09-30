import 'package:dilbaz_app/features/placement/application/placement_controller.dart';
import 'package:dilbaz_app/features/placement/application/placement_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One word of the yes/no vocabulary part. Answers come fast, so the two
/// buttons are large and always in the same place.
class WordView extends ConsumerWidget {
  const new({required this.state, super.key});

  final PlacementWord state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(placementControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: (state.number - 1) / state.total),
          const SizedBox(height: 8),
          Text(
            l10n.placementProgress(state.number, state.total),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  state.word,
                  // The word is English, whatever the interface language.
                  locale: const Locale('en'),
                  style: theme.textTheme.displaySmall,
                ),
              ),
            ),
          ),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: OutlinedButton(
                  style: _large,
                  onPressed: () => controller.answerWord(known: false),
                  child: Text(l10n.placementWordUnknown),
                ),
              ),
              Expanded(
                child: FilledButton(
                  style: _large,
                  onPressed: () => controller.answerWord(known: true),
                  child: Text(l10n.placementWordKnown),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static final _large = ButtonStyle(
    minimumSize: WidgetStateProperty.all(const Size.fromHeight(64)),
  );
}
