import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// A notification channel: how the system lists and groups the app's
/// notifications. Its name and description are the learner's to read.
typedef NotificationChannel = ({String id, String name, String description});

/// A note set ahead: when it goes out, and what it says.
typedef ScheduledNote = ({DateTime at, String text});

/// The device's notifications (docs/09-ux-motivation.md §6): the daily
/// invitation, set ahead, and notes shown at once.
abstract interface class NotificationGateway {
  /// Whether the system lets the app show notifications now.
  Future<bool> allowed();

  /// Replaces what is set ahead with [notes], on [channel].
  Future<void> setAhead(NotificationChannel channel, List<ScheduledNote> notes);

  /// Shows [text] at once, on [channel].
  Future<void> show(NotificationChannel channel, String text);
}

/// Where notifications are not set up: the web has no scheduled ones, and
/// Android comes first (docs/09 §6).
class NoNotificationGateway implements NotificationGateway {
  const new();

  @override
  Future<bool> allowed() async => false;

  @override
  Future<void> setAhead(
    NotificationChannel channel,
    List<ScheduledNote> notes,
  ) async {}

  @override
  Future<void> show(NotificationChannel channel, String text) async {}
}

/// Android notifications (flutter_local_notifications).
class LocalNotificationGateway implements NotificationGateway {
  new([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;

  /// Ids of the notes set ahead, one a day; and of the note shown at once.
  static const _firstAhead = 100;
  static const maxAhead = 14;
  static const _atOnce = 200;

  Future<void> _init() => _ready ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
        ),
      )
      .then((_) {});

  @override
  Future<bool> allowed() async {
    await _init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<void> setAhead(
    NotificationChannel channel,
    List<ScheduledNote> notes,
  ) async {
    await _init();
    for (var i = 0; i < maxAhead; i++) {
      await _plugin.cancel(id: _firstAhead + i);
    }
    for (final (i, note) in notes.take(maxAhead).indexed) {
      await _plugin.zonedSchedule(
        id: _firstAhead + i,
        // Each day's own instant: the learner's clock is applied before.
        scheduledDate: tz.TZDateTime.from(note.at.toUtc(), tz.UTC),
        notificationDetails: _details(channel),
        // An invitation needs no exact alarm.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        body: note.text,
      );
    }
  }

  @override
  Future<void> show(NotificationChannel channel, String text) async {
    await _init();
    await _plugin.show(
      id: _atOnce,
      body: text,
      notificationDetails: _details(channel),
    );
  }

  static NotificationDetails _details(NotificationChannel channel) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
        ),
      );
}
