import 'package:dilbaz_app/app/app.dart';
import 'package:dilbaz_app/core/config/app_env.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const env = AppEnv.fromDefines;
  if (!env.isComplete) {
    throw StateError(
      'missing_env: run with --dart-define-from-file=env/<name>.json '
      '(see app/env.example.json)',
    );
  }
  await Supabase.initialize(
    url: env.supabaseUrl,
    publishableKey: env.supabasePublishableKey,
  );
  runApp(const ProviderScope(child: DilbazApp()));
}
