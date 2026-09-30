import 'dart:async';

import 'package:dilbaz_app/features/onboarding/application/onboarding_controller.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/step_header.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Step 8: consent to audio recording, asked before the microphone
/// (docs/14 §4), and consent to the AI provider that may use the learner's
/// texts (ADR-0009). Both are the learner's own choice and neither is
/// needed to go on.
class VoiceStep extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final (answers, busy) = ref.watch(
      onboardingControllerProvider.select((s) => (s.answers, s.busy)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          title: l10n.onboardingVoiceTitle,
          body: l10n.onboardingAudioBody,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.onboardingAudioConsent),
          subtitle: answers.audioConsent
              ? null
              : Text(l10n.onboardingAudioOffNote),
          value: answers.audioConsent,
          onChanged: busy
              ? null
              : (granted) =>
                    unawaited(controller.setAudioConsent(granted: granted)),
        ),
        const Divider(height: 40),
        Text(
          l10n.onboardingAiBody,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.onboardingAiConsent),
          value: answers.aiDataConsent,
          onChanged: (granted) =>
              controller.answer((a) => a.copyWith(aiDataConsent: granted)),
        ),
      ],
    );
  }
}
