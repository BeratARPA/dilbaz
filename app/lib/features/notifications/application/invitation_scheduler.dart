import 'dart:async';
import 'dart:ui' show Locale;

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/notifications/notification_gateway.dart';
import 'package:dilbaz_app/data/notifications/notification_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'invitation_scheduler.g.dart';

/// The learner's daily invitation settings, as they change.
@Riverpod(keepAlive: true)
Stream<InvitationSettings?> invitationSettings(Ref ref, String userId) =>
    ref.watch(profileRepositoryProvider).watchInvitation(userId);

/// When the learner's latest session began, as new ones come.
@Riverpod(keepAlive: true)
Stream<DateTime?> latestSession(Ref ref, String userId) =>
    ref.watch(sessionRepositoryProvider).watchLatestStart(userId);

/// Sets the daily invitation ahead (docs/09-ux-motivation.md §6): at the
/// learner's anchor, once a day, not on a day already studied, never in
/// quiet hours, at most a week ahead ([invitationTimes]). It sets them
/// again when the profile changes, after each session, and when the app
/// comes back (a new day may have begun).
///
/// Its state is the times set ahead.
@Riverpod(keepAlive: true)
class InvitationScheduler extends _$InvitationScheduler {
  @override
  Future<List<DateTime>> build() async {
    final userId = ref.watch(currentUserIdProvider).value;
    if (userId == null) return const [];
    final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
    ref.onDispose(lifecycle.dispose);
    final settingsLater = ref.watch(invitationSettingsProvider(userId).future);
    final latestLater = ref.watch(latestSessionProvider(userId).future);
    final gateway = ref.watch(notificationGatewayProvider);
    final now = ref.watch(clockProvider)().toLocal();
    final settings = await settingsLater;
    final latest = await latestLater;
    final time = settings?.time;
    final times =
        settings != null &&
            settings.wanted &&
            time != null &&
            await gateway.allowed()
        ? invitationTimes(
            now: now,
            anchor: time,
            studiedToday:
                latest != null && !latest.isBefore(startOfLocalDay(now)),
            quiet: settings.quiet,
          )
        : const <DateTime>[];
    final l10n = lookupAppLocalizations(const Locale('tr'));
    await gateway.setAhead(invitationChannel(l10n), [
      for (final at in times)
        (at: at, text: invitationText(l10n, settings?.anchor, at)),
    ]);
    return times;
  }
}

/// The channel the invitations go out on.
NotificationChannel invitationChannel(AppLocalizations l10n) => (
  id: 'daily_invitation',
  name: l10n.notifyInvitationChannel,
  description: l10n.notifyInvitationChannelDescription,
);

/// What the invitation of [at] says: by the anchor on even days, a
/// speaking task on odd ones, so that it does not read the same each day.
String invitationText(AppLocalizations l10n, String? anchor, DateTime at) {
  if (at.day.isOdd) return l10n.notifyInvitationSpeaking;
  return switch (anchor) {
    'morning_coffee' => l10n.notifyInvitationMorningCoffee,
    'lunch_break' => l10n.notifyInvitationLunchBreak,
    'after_dinner' => l10n.notifyInvitationAfterDinner,
    'before_bed' => l10n.notifyInvitationBeforeBed,
    _ => l10n.notifyInvitationAnyTime,
  };
}
