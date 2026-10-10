import 'package:dilbaz_app/features/onboarding/presentation/steps/step_header.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Step 6: why the app asks for the notification permission. The buttons
/// that answer it are in the flow's bottom bar.
class NotificationsStep extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return StepHeader(
      title: l10n.onboardingNotifyTitle,
      body: l10n.onboardingNotifyBody,
    );
  }
}
