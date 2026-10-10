import 'package:permission_handler/permission_handler.dart';

/// Asks the system for the permissions the app needs; each is asked for
/// where its reason is on screen (docs/09-ux-motivation.md §5.1).
abstract interface class PermissionGateway {
  /// Asks to show notifications. True if granted.
  Future<bool> requestNotifications();

  /// Asks to use the microphone. True if granted.
  Future<bool> requestMicrophone();
}

class DevicePermissionGateway implements PermissionGateway {
  const new();

  @override
  Future<bool> requestNotifications() async =>
      (await Permission.notification.request()).isGranted;

  @override
  Future<bool> requestMicrophone() async =>
      (await Permission.microphone.request()).isGranted;
}
