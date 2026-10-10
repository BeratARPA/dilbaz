import 'package:dilbaz_app/features/onboarding/application/onboarding_controller.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/step_header.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Step 2: the learner's name and the course.
class NameStep extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<NameStep> createState() => _NameStepState();
}

class _NameStepState extends ConsumerState<NameStep> {
  late final _name = TextEditingController(
    text: ref.read(onboardingControllerProvider).answers.displayName,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = ref.read(onboardingControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(title: l10n.onboardingNameTitle),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.givenName],
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: l10n.onboardingNameLabel),
          onChanged: (value) =>
              controller.answer((a) => a.copyWith(displayName: value)),
          onSubmitted: (_) => controller.next(),
        ),
        const SizedBox(height: 24),
        Text(l10n.onboardingCourseNote),
      ],
    );
  }
}
