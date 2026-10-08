import 'package:dilbaz_app/data/notifications/notification_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notification_providers.g.dart';

/// Android's notifications; elsewhere none for now (docs/09 §6).
@Riverpod(keepAlive: true)
NotificationGateway notificationGateway(Ref ref) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? LocalNotificationGateway()
    : const NoNotificationGateway();
