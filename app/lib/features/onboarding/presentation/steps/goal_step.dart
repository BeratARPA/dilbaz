import 'package:dilbaz_app/features/onboarding/application/onboarding_controller.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/step_header.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Goal codes with their labels; the codes become the profile's interests.
Map<String, String> goalLabels(AppLocalizations l10n) => {
  'conversation': l10n.goalConversation,
  'travel': l10n.goalTravel,
  'work': l10n.goalWork,
  'media': l10n.goalMedia,
  'study': l10n.goalStudy,
};

/// Step 3: what the learner wants to do with the language in a year.
class GoalStep extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<GoalStep> createState() => _GoalStepState();
}

class _GoalStepState extends ConsumerState<GoalStep> {
  late final _text = TextEditingController(
    text: ref.read(onboardingControllerProvider).answers.goalText,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final chosen = ref.watch(
      onboardingControllerProvider.select((s) => s.answers.goals),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          title: l10n.onboardingGoalTitle,
          body: l10n.onboardingGoalHint,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final MapEntry(key: code, value: label) in goalLabels(
              l10n,
            ).entries)
              FilterChip(
                label: Text(label),
                selected: chosen.contains(code),
                onSelected: (selected) => controller.answer(
                  (a) => a.copyWith(
                    goals: selected
                        ? {...a.goals, code}
                        : a.goals.difference({code}),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _text,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          decoration: InputDecoration(labelText: l10n.onboardingGoalTextLabel),
          onChanged: (value) =>
              controller.answer((a) => a.copyWith(goalText: value)),
        ),
      ],
    );
  }
}
