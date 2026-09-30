import 'package:dilbaz_app/features/onboarding/presentation/steps/step_header.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Step 1: the three principles the app is built on.
class WelcomeStep extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final principles = [
      (l10n.onboardingPrinciple1, l10n.onboardingPrinciple1Detail),
      (l10n.onboardingPrinciple2, l10n.onboardingPrinciple2Detail),
      (l10n.onboardingPrinciple3, l10n.onboardingPrinciple3Detail),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(title: l10n.onboardingWelcomeTitle),
        for (final (title, detail) in principles)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(detail, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
      ],
    );
  }
}
