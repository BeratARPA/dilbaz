import 'dart:async';

import 'package:dilbaz_app/features/onboarding/application/onboarding_controller.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_state.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/anchor_step.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/goal_step.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/level_step.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/name_step.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/notifications_step.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/partner_step.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/time_step.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/voice_step.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/welcome_step.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The welcome flow of the first start (docs/09-ux-motivation.md §5.1).
/// Finishing it saves the profile; the router then opens the Today tab.
class OnboardingScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(onboardingControllerProvider);
    final steps = OnboardingStep.values.length;
    return PopScope(
      // The system back button walks the steps like the one on screen and
      // leaves the app only from the first step.
      canPop: state.isFirst,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || state.busy) return;
        ref.read(onboardingControllerProvider.notifier).back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              LinearProgressIndicator(
                value: (state.step.index + 1) / steps,
                semanticsLabel: l10n.onboardingStepOf(
                  state.step.index + 1,
                  steps,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  // Each step starts at its top.
                  key: ValueKey(state.step),
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  child: switch (state.step) {
                    OnboardingStep.welcome => const WelcomeStep(),
                    OnboardingStep.name => const NameStep(),
                    OnboardingStep.goal => const GoalStep(),
                    OnboardingStep.time => const TimeStep(),
                    OnboardingStep.anchor => const AnchorStep(),
                    OnboardingStep.notifications => const NotificationsStep(),
                    OnboardingStep.partner => const PartnerStep(),
                    OnboardingStep.voice => const VoiceStep(),
                    OnboardingStep.level => const LevelStep(),
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _Actions(state: state),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Back on the left, the step's way forward on the right. At large text
/// sizes the buttons stack instead of running off the screen.
class _Actions extends ConsumerWidget {
  const new({required this.state});

  final OnboardingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final busy = state.busy;
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.end,
      overflowSpacing: 8,
      children: [
        if (state.isFirst)
          const SizedBox.shrink()
        else
          TextButton(
            onPressed: busy ? null : controller.back,
            child: Text(l10n.onboardingBack),
          ),
        OverflowBar(
          spacing: 8,
          overflowAlignment: OverflowBarAlignment.end,
          overflowSpacing: 8,
          children: switch (state.step) {
            OnboardingStep.welcome => [
              FilledButton(
                onPressed: controller.next,
                child: Text(l10n.onboardingStart),
              ),
            ],
            OnboardingStep.notifications => [
              TextButton(
                onPressed: busy ? null : controller.skipNotifications,
                child: Text(l10n.onboardingNotifyLater),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => unawaited(controller.askNotifications()),
                child: Text(l10n.onboardingNotifyAllow),
              ),
            ],
            OnboardingStep.partner => [
              FilledButton(
                onPressed: busy ? null : controller.next,
                child: Text(
                  state.team == null
                      ? l10n.onboardingSkip
                      : l10n.onboardingNext,
                ),
              ),
            ],
            OnboardingStep.level => [
              FilledButton(
                onPressed: busy ? null : () => unawaited(controller.finish()),
                child: Text(l10n.onboardingFinish),
              ),
            ],
            _ => [
              FilledButton(
                onPressed: state.canGoOn && !busy ? controller.next : null,
                child: Text(l10n.onboardingNext),
              ),
            ],
          },
        ),
      ],
    );
  }
}
