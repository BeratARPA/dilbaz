import 'package:dilbaz_app/features/placement/application/placement_controller.dart';
import 'package:dilbaz_app/features/placement/application/placement_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One grammar question: the sentence with its gap and the choices. No
/// answer is marked right or wrong (docs/06 §1).
class QuestionView extends ConsumerWidget {
  const new({required this.state, super.key});

  final PlacementQuestion state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(placementControllerProvider.notifier);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            l10n.placementQuestionNumber(state.number),
            style: theme.textTheme.bodySmall,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              state.stem,
              locale: const Locale('en'),
              style: theme.textTheme.headlineSmall,
            ),
          ),
          for (final option in state.options)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => controller.choose(option),
              child: Text(option, locale: const Locale('en')),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => controller.choose(null),
            child: Text(l10n.placementNotSure),
          ),
        ],
      ),
    );
  }
}
