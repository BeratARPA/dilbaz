import 'dart:async';

import 'package:dilbaz_app/app/day_time_picker.dart';
import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/data/repositories/settings_change.dart';
import 'package:dilbaz_app/features/auth/application/session_controller.dart';
import 'package:dilbaz_app/features/onboarding/presentation/steps/anchor_step.dart';
import 'package:dilbaz_app/features/settings/application/settings_controller.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings v1 (docs/09-ux-motivation.md §5.12): the day's time, the
/// anchor, the daily invitation and quiet hours, silent mode, the consents
/// and the learner's data (docs/14 §4). Each change is saved at once.
class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  static const budgets = [5, 10, 15, 20, 30, 45, 60];
  static const days = [3, 4, 5, 6, 7];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      // Every row is built: a lazy list leaves the lower rows unbuilt on a
      // small screen with large text.
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (settings != null) ..._profile(context, ref, settings),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(l10n.signOut),
              onTap: () => unawaited(
                ref.read(sessionControllerProvider.notifier).signOut(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _profile(
    BuildContext context,
    WidgetRef ref,
    ProfileSettings settings,
  ) {
    final l10n = context.l10n;
    final controller = ref.read(settingsControllerProvider.notifier);

    Future<void> change(SettingsChange change) async {
      // It may come after a time picker closed.
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final outcome = await controller.change(change);
      final text = switch ((outcome, change)) {
        (SettingsOutcome.permissionDenied, InvitationChange()) =>
          l10n.settingsNotificationsDenied,
        (SettingsOutcome.permissionDenied, _) => l10n.settingsMicrophoneDenied,
        (SettingsOutcome.offline, _) => l10n.settingsOffline,
        (SettingsOutcome.failed, _) => l10n.settingsFailed,
        (SettingsOutcome.done, _) => null,
      };
      if (text != null) messenger.showSnackBar(SnackBar(content: Text(text)));
    }

    Future<String?> pick(String initial) => pickDayTime(context, initial);
    final quiet = settings.quietHours;
    return [
      _Section(l10n.settingsStudySection),
      _Choices(
        title: l10n.onboardingTimeTitle,
        children: [
          for (final minutes in budgets)
            ChoiceChip(
              label: Text(l10n.onboardingBudgetMinutes(minutes)),
              selected: settings.timeBudgetMin == minutes,
              onSelected: (_) =>
                  unawaited(change(SettingsChange.budget(minutes))),
            ),
        ],
      ),
      _Choices(
        title: l10n.onboardingWeeklyDaysTitle,
        children: [
          for (final count in days)
            ChoiceChip(
              label: Text(l10n.onboardingWeeklyDays(count)),
              selected: settings.weeklyDaysGoal == count,
              onSelected: (_) =>
                  unawaited(change(SettingsChange.daysGoal(count))),
            ),
        ],
      ),
      _Choices(
        title: l10n.onboardingAnchorTitle,
        children: [
          for (final MapEntry(key: code, value: label) in anchorLabels(
            l10n,
          ).entries)
            ChoiceChip(
              label: Text(label),
              selected: settings.anchor == code,
              onSelected: (_) => unawaited(
                change(
                  SettingsChange.anchor(anchor: code, time: anchorTimes[code]!),
                ),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.schedule),
            label: Text(l10n.onboardingAnchorTime(settings.anchorTime)),
            onPressed: () async {
              final time = await pick(settings.anchorTime);
              if (time == null) return;
              await change(
                SettingsChange.anchor(anchor: settings.anchor, time: time),
              );
            },
          ),
        ],
      ),
      _Section(l10n.settingsInvitationSection),
      SwitchListTile(
        title: Text(l10n.settingsInvitation),
        subtitle: Text(l10n.notifyInvitationChannelDescription),
        value: settings.dailyInvitation,
        onChanged: (wanted) =>
            unawaited(change(SettingsChange.invitation(wanted: wanted))),
      ),
      SwitchListTile(
        title: Text(l10n.settingsQuietHours),
        value: quiet != null,
        onChanged: (on) => unawaited(
          change(
            SettingsChange.quietHours(on ? (from: '22:30', to: '08:00') : null),
          ),
        ),
      ),
      if (quiet != null)
        _Choices(
          children: [
            ActionChip(
              label: Text(l10n.settingsQuietFrom(quiet.from)),
              onPressed: () async {
                final time = await pick(quiet.from);
                if (time == null) return;
                await change(
                  SettingsChange.quietHours((from: time, to: quiet.to)),
                );
              },
            ),
            ActionChip(
              label: Text(l10n.settingsQuietTo(quiet.to)),
              onPressed: () async {
                final time = await pick(quiet.to);
                if (time == null) return;
                await change(
                  SettingsChange.quietHours((from: quiet.from, to: time)),
                );
              },
            ),
          ],
        ),
      _Section(l10n.settingsAnswersSection),
      SwitchListTile(
        title: Text(l10n.settingsSilentMode),
        subtitle: Text(l10n.settingsSilentModeNote),
        value: settings.silentMode,
        onChanged: (on) => unawaited(change(SettingsChange.silentMode(on: on))),
      ),
      ListTile(
        leading: const Icon(Icons.mic_none),
        title: Text(l10n.microphoneCheckTitle),
        onTap: () => unawaited(context.push(AppRoutes.microphoneCheck)),
      ),
      _Section(l10n.settingsConsentsSection),
      SwitchListTile(
        title: Text(l10n.onboardingAudioConsent),
        subtitle: Text(l10n.onboardingAudioBody),
        isThreeLine: true,
        value: settings.audioConsent,
        onChanged: (granted) =>
            unawaited(change(SettingsChange.audioConsent(granted: granted))),
      ),
      SwitchListTile(
        title: Text(l10n.onboardingAiConsent),
        subtitle: Text(l10n.onboardingAiBody),
        isThreeLine: true,
        value: settings.aiDataConsent,
        onChanged: (granted) =>
            unawaited(change(SettingsChange.aiDataConsent(granted: granted))),
      ),
      _Section(l10n.settingsDataSection),
      ListTile(
        leading: const Icon(Icons.ios_share),
        title: Text(l10n.settingsExport),
        subtitle: Text(l10n.settingsExportNote),
        onTap: () => unawaited(controller.export()),
      ),
      ListTile(
        leading: const Icon(Icons.delete_outline),
        title: Text(l10n.settingsDeleteAll),
        onTap: () => unawaited(_deleteAll(context, controller)),
      ),
      const Divider(),
    ];
  }

  static Future<void> _deleteAll(
    BuildContext context,
    SettingsController controller,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsDeleteTitle),
        content: Text(l10n.settingsDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.settingsDeleteCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsDeleteConfirm),
          ),
        ],
      ),
    );
    if (sure != true) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.settingsDeleting)));
    final outcome = await controller.deleteAll();
    messenger.hideCurrentSnackBar();
    // Done: without a profile, the welcome flow follows by itself.
    final text = switch (outcome) {
      SettingsOutcome.offline => l10n.settingsOffline,
      SettingsOutcome.done => null,
      _ => l10n.settingsFailed,
    };
    if (text != null) messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}

class _Section extends StatelessWidget {
  const new(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}

/// A question with its choices, wrapping on narrow screens.
class _Choices extends StatelessWidget {
  const new({required this.children, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        if (title case final title?) Text(title),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    ),
  );
}
