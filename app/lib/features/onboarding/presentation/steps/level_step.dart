import 'package:dilbaz_app/features/onboarding/application/onboarding_controller.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/step_header.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Level codes the learner can start at, with how each is described.
Map<String, String> levelLabels(AppLocalizations l10n) => {
  'A0': l10n.levelA0,
  'A1': l10n.levelA1,
  'A2': l10n.levelA2,
  'B1': l10n.levelB1,
};

/// Step 9: a rough starting level, until the placement test is taken
/// (docs/04-learner-model.md §10).
class LevelStep extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final level = ref.watch(
      onboardingControllerProvider.select((s) => s.answers.level),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          title: l10n.onboardingLevelTitle,
          body: l10n.onboardingLevelBody,
        ),
        for (final MapEntry(key: code, value: label) in levelLabels(
          l10n,
        ).entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: level == code,
              onSelected: (_) =>
                  controller.answer((a) => a.copyWith(level: code)),
            ),
          ),
      ],
    );
  }
}
