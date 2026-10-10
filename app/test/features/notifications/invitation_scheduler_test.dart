import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/notifications/notification_gateway.dart';
import 'package:dilbaz_app/data/notifications/notification_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/session_repository.dart';
import 'package:dilbaz_app/features/notifications/application/invitation_scheduler.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/pump_app.dart';

/// Notifications kept in memory.
final class FakeNotificationGateway implements NotificationGateway {
  bool permitted = true;
  final ahead = <List<ScheduledNote>>[];
  final channels = <NotificationChannel>[];
  final shown = <String>[];

  @override
  Future<bool> allowed() async => permitted;

  @override
  Future<void> setAhead(
    NotificationChannel channel,
    List<ScheduledNote> notes,
  ) async {
    channels.add(channel);
    ahead.add(notes);
  }

  @override
  Future<void> show(NotificationChannel channel, String text) async =>
      shown.add(text);
}

const InvitationSettings coffee = (
  wanted: true,
  anchor: 'morning_coffee',
  time: (hour: 8, minute: 30),
  quiet: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakeNotificationGateway gateway;
  late ProviderContainer container;
  // 07:00 on the learner's clock.
  final now = DateTime(2026, 10, 8, 7);

  setUp(() {
    db = memoryDatabase();
    profiles = FakeProfileRepository(onboarded: true)..invitation = coffee;
    gateway = FakeNotificationGateway();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWith(
          (ref) => Stream.value(FakeAuthRepository.id),
        ),
        profileRepositoryProvider.overrideWithValue(profiles),
        notificationGatewayProvider.overrideWithValue(gateway),
        clockProvider.overrideWithValue(now.toUtc),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<DateTime>> scheduled() async {
    final sub = container.listen(invitationSchedulerProvider, (_, _) {});
    addTearDown(sub.close);
    // The user id comes first; the schedule then follows it.
    await container.read(currentUserIdProvider.future);
    return await container.read(invitationSchedulerProvider.future);
  }

  test('a week of invitations at the anchor, worded by the anchor', () async {
    final times = await scheduled();
    expect(times, hasLength(7));
    expect(times.first, DateTime(2026, 10, 8, 8, 30));
    final notes = gateway.ahead.last;
    expect([for (final note in notes) note.at], times);
    final l10n = trStrings;
    // The 8th is even: the anchor's own words; the 9th: a speaking task.
    expect(notes[0].text, l10n.notifyInvitationMorningCoffee);
    expect(notes[1].text, l10n.notifyInvitationSpeaking);
    expect(gateway.channels.last.name, l10n.notifyInvitationChannel);
  });

  test('a session today moves the next invitation to tomorrow', () async {
    expect((await scheduled()).first, DateTime(2026, 10, 8, 8, 30));
    await DriftSessionRepository(db).record(
      userId: FakeAuthRepository.id,
      courseId: 'course-1',
      deviceId: 'device-1',
      startedAt: now.toUtc(),
      endedAt: now.add(const Duration(minutes: 5)).toUtc(),
      strands: {Strand.language: const Duration(minutes: 5)},
    );
    // The session stream wakes the scheduler.
    await pumpEventQueue();
    final times = await container.read(invitationSchedulerProvider.future);
    expect(times.first, DateTime(2026, 10, 9, 8, 30));
    expect(gateway.ahead.last.first.at, DateTime(2026, 10, 9, 8, 30));
  });

  test('none when not wanted, not allowed, or in quiet hours', () async {
    profiles.invitation = (
      wanted: false,
      anchor: 'morning_coffee',
      time: (hour: 8, minute: 30),
      quiet: null,
    );
    expect(await scheduled(), isEmpty);
    expect(gateway.ahead.last, isEmpty);

    profiles.setInvitation(coffee);
    await pumpEventQueue();
    expect(
      await container.read(invitationSchedulerProvider.future),
      hasLength(7),
    );

    gateway.permitted = false;
    container.invalidate(invitationSchedulerProvider);
    expect(await container.read(invitationSchedulerProvider.future), isEmpty);

    gateway.permitted = true;
    profiles.setInvitation((
      wanted: true,
      anchor: 'before_bed',
      time: (hour: 23, minute: 0),
      quiet: const QuietHours(
        from: (hour: 22, minute: 30),
        to: (hour: 8, minute: 0),
      ),
    ));
    await pumpEventQueue();
    expect(await container.read(invitationSchedulerProvider.future), isEmpty);
    expect(gateway.ahead.last, isEmpty);
  });

  test('coming back to the app sets them again', () async {
    await scheduled();
    final before = gateway.ahead.length;
    final binding = TestWidgetsFlutterBinding.instance;
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(binding.handleAppLifecycleStateChanged);
    await container.read(invitationSchedulerProvider.future);
    expect(gateway.ahead.length, before + 1);
  });

  test('the words by anchor, and without one', () {
    final l10n = trStrings;
    final even = DateTime(2026, 10, 8, 20);
    expect(
      invitationText(l10n, 'lunch_break', even),
      l10n.notifyInvitationLunchBreak,
    );
    expect(
      invitationText(l10n, 'after_dinner', even),
      l10n.notifyInvitationAfterDinner,
    );
    expect(
      invitationText(l10n, 'before_bed', even),
      l10n.notifyInvitationBeforeBed,
    );
    expect(invitationText(l10n, null, even), l10n.notifyInvitationAnyTime);
  });
}
