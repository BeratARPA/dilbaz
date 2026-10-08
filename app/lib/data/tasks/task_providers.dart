import 'package:dilbaz_app/data/db/database_provider.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_store.dart';
import 'package:dilbaz_app/data/tasks/task_content_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'task_providers.g.dart';

@riverpod
TaskContentRepository taskContentRepository(Ref ref) =>
    DriftTaskContentRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
RecordingRepository recordingRepository(Ref ref) =>
    DriftRecordingRepository(ref.watch(appDatabaseProvider));

/// Recordings stay until retention or the learner removes them; a cache
/// folder could lose the "before" of a before/after comparison.
@Riverpod(keepAlive: true)
RecordingStore recordingStore(Ref ref) => RecordingStore(
  directory: () async => (await getApplicationSupportDirectory()).path,
);
