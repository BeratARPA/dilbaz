import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/sync/sync_remote.dart';
import 'package:dilbaz_app/data/sync/sync_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'sync_providers.g.dart';

/// Requires `Supabase.initialize` (main.dart); tests override it with a fake.
@Riverpod(keepAlive: true)
SyncRemote syncRemote(Ref ref) => SupabaseSyncRemote(Supabase.instance.client);

@Riverpod(keepAlive: true)
SyncRepository syncRepository(Ref ref) => DriftSyncRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(syncRemoteProvider),
  ref.watch(deviceRepositoryProvider),
  now: ref.watch(clockProvider),
);
