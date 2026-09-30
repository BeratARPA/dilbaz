import 'package:dilbaz_app/features/onboarding/application/onboarding_controller.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/step_header.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Habit anchors with their usual times.
const anchorTimes = {
  'morning_coffee': '08:30',
  'lunch_break': '12:30',
  'after_dinner': '20:00',
  'before_bed': '22:30',
};

Map<String, String> anchorLabels(AppLocalizations l10n) => {
  'morning_coffee': l10n.anchorMorningCoffee,
  'lunch_break': l10n.anchorLunchBreak,
  'after_dinner': l10n.anchorAfterDinner,
  'before_bed': l10n.anchorBeforeBed,
};

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// Step 5: the existing habit the daily practice is tied to, and its time.
class AnchorStep extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final answers = ref.watch(
      onboardingControllerProvider.select((s) => s.answers),
    );

    Future<void> pickTime() async {
      final [hour, minute] = answers.anchorTime.split(':');
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: int.parse(hour),
          minute: int.parse(minute),
        ),
        // The anchor time is kept and shown as `HH:mm`, whatever the
        // clock setting of the device.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (picked == null) return;
      controller.answer(
        (a) => a.copyWith(
          anchorTime: '${_twoDigits(picked.hour)}:${_twoDigits(picked.minute)}',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          title: l10n.onboardingAnchorTitle,
          body: l10n.onboardingAnchorNote,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final MapEntry(key: code, value: label) in anchorLabels(
              l10n,
            ).entries)
              ChoiceChip(
                label: Text(label),
                selected: answers.anchor == code,
                onSelected: (_) => controller.answer(
                  (a) =>
                      a.copyWith(anchor: code, anchorTime: anchorTimes[code]!),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: pickTime,
          icon: const Icon(Icons.schedule),
          label: Text(l10n.onboardingAnchorTime(answers.anchorTime)),
        ),
      ],
    );
  }
}
