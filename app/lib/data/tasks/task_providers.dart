import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/tasks/monthly_test_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_files.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_store.dart';
import 'package:dilbaz_app/data/tasks/task_content_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'task_providers.g.dart';

@riverpod
TaskContentRepository taskContentRepository(Ref ref) =>
    DriftTaskContentRepository(ref.watch(appDatabaseProvider));

/// Both stamp their rows with the app's clock, which tests fix.
@Riverpod(keepAlive: true)
RecordingRepository recordingRepository(Ref ref) => DriftRecordingRepository(
  ref.watch(appDatabaseProvider),
  now: ref.watch(clockProvider),
);

@Riverpod(keepAlive: true)
MonthlyTestRepository monthlyTestRepository(Ref ref) =>
    DriftMonthlyTestRepository(
      ref.watch(appDatabaseProvider),
      now: ref.watch(clockProvider),
    );

/// Recordings stay until retention or the learner removes them; a cache
/// folder could lose the "before" of a before/after comparison.
@Riverpod(keepAlive: true)
RecordingStore recordingStore(Ref ref) => RecordingStore(
  directory: () async => (await getApplicationSupportDirectory()).path,
);

/// Requires `Supabase.initialize` (main.dart); tests override it with a fake.
@Riverpod(keepAlive: true)
AudioRemote audioRemote(Ref ref) =>
    SupabaseAudioRemote(Supabase.instance.client);

@Riverpod(keepAlive: true)
RecordingFiles recordingFiles(Ref ref) => DriftRecordingFiles(
  ref.watch(appDatabaseProvider),
  ref.watch(recordingStoreProvider),
  ref.watch(audioRemoteProvider),
  now: ref.watch(clockProvider),
);
