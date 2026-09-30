import 'package:dilbaz_app/features/onboarding/application/onboarding_controller.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/step_header.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Daily budgets offered, in minutes (docs/09 §5.1).
const budgetOptions = [5, 15, 30];

/// Weekly day goals offered.
const weeklyDayOptions = [3, 4, 5, 6, 7];

/// Step 4: the daily time budget and the weekly days goal.
class TimeStep extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final answers = ref.watch(
      onboardingControllerProvider.select((s) => s.answers),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(title: l10n.onboardingTimeTitle),
        SegmentedButton<int>(
          segments: [
            for (final minutes in budgetOptions)
              ButtonSegment(
                value: minutes,
                label: Text(l10n.onboardingBudgetMinutes(minutes)),
              ),
          ],
          selected: {answers.timeBudgetMin},
          onSelectionChanged: (selection) => controller.answer(
            (a) => a.copyWith(timeBudgetMin: selection.single),
          ),
        ),
        const SizedBox(height: 12),
        Text(l10n.onboardingTimeNote),
        const SizedBox(height: 32),
        Text(
          l10n.onboardingWeeklyDaysTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (final days in weeklyDayOptions)
              ButtonSegment(
                value: days,
                label: Text('$days'),
                tooltip: l10n.onboardingWeeklyDays(days),
              ),
          ],
          selected: {answers.weeklyDaysGoal},
          onSelectionChanged: (selection) => controller.answer(
            (a) => a.copyWith(weeklyDaysGoal: selection.single),
          ),
        ),
      ],
    );
  }
}
