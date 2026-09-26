import 'package:flutter/foundation.dart';

/// Build-time configuration from `--dart-define-from-file=env/<name>.json`.
///
/// Only public values: the project URL and the publishable key. Secret keys
/// never enter the app (docs/12-architecture.md §8).
@immutable
class AppEnv {
  const new({required this.supabaseUrl, required this.supabasePublishableKey});

  static const fromDefines = AppEnv(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  final String supabaseUrl;
  final String supabasePublishableKey;

  bool get isComplete =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
