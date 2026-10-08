import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/my_data/my_data_remote.dart';
import 'package:dilbaz_app/data/my_data/my_data_repository.dart';
import 'package:dilbaz_app/data/share/file_sharer.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'my_data_providers.g.dart';

/// Requires `Supabase.initialize` (main.dart); tests override it with a fake.
@Riverpod(keepAlive: true)
MyDataRemote myDataRemote(Ref ref) =>
    SupabaseMyDataRemote(Supabase.instance.client);

@Riverpod(keepAlive: true)
MyDataRepository myDataRepository(Ref ref) => DriftMyDataRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(myDataRemoteProvider),
  ref.watch(audioRemoteProvider),
  ref.watch(recordingStoreProvider),
);

/// The system's share sheet; tests override it with a fake.
@Riverpod(keepAlive: true)
FileSharer fileSharer(Ref ref) => const SharePlusFileSharer();
