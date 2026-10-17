import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/together/pair_task_repository.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'together_providers.g.dart';

/// Requires `Supabase.initialize` (main.dart); tests override it with a fake.
@Riverpod(keepAlive: true)
TogetherRepository togetherRepository(Ref ref) =>
    SupabaseTogetherRepository(Supabase.instance.client);

/// The learner's own record of information gap tasks, stamped with the
/// app's clock.
@Riverpod(keepAlive: true)
PairTaskRepository pairTaskRepository(Ref ref) => DriftPairTaskRepository(
  ref.watch(appDatabaseProvider),
  now: ref.watch(clockProvider),
);
