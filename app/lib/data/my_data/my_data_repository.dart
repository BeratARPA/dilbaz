import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/my_data/my_data_remote.dart';
import 'package:dilbaz_app/data/sync/sync_rows.dart';
import 'package:dilbaz_app/data/tasks/recording_files.dart';
import 'package:dilbaz_app/data/tasks/recording_store.dart';
import 'package:drift/drift.dart';

/// The learner's rights over their data (docs/14-security-privacy.md §4):
/// to take it all away, and to delete it.
abstract interface class MyDataRepository {
  /// Everything of [userId] on this device, in the server's tables and
  /// column names, as one JSON document.
  Future<Map<String, Object?>> export(String userId, {required DateTime at});

  /// Deletes the learner's audio on the server, then their rows there,
  /// then everything of theirs on this device. Nothing here is deleted
  /// unless the server's part went through.
  Future<Result<void, MyDataFailure>> deleteAll(String userId);
}

class DriftMyDataRepository implements MyDataRepository {
  new(this._db, this._remote, this._audio, this._store);

  final AppDatabase _db;
  final MyDataRemote _remote;
  final AudioRemote _audio;
  final RecordingStore _store;

  /// The format of an export, for whoever reads it later.
  static const format = 'dilbaz-export@1';

  /// The rows of [synced] that belong to [userId].
  Expression<bool> _owned(SyncedTable synced, String userId) {
    final column =
        synced.table.columnsByName['profile_id'] ??
        synced.table.columnsByName['id']!;
    return (column as GeneratedColumn<String>).equals(userId);
  }

  @override
  Future<Map<String, Object?>> export(
    String userId, {
    required DateTime at,
  }) async => {
    'format': format,
    'exported_at': at.toUtc().toIso8601String(),
    'profile_id': userId,
    'tables': {
      for (final synced in syncedTables(_db))
        synced.table.actualTableName: [
          for (final row in await (_db.select(
            synced.table,
          )..where((_) => _owned(synced, userId))).get())
            SyncRows.toServer(synced.table, row! as Insertable),
        ],
    },
  };

  @override
  Future<Result<void, MyDataFailure>> deleteAll(String userId) async {
    final listed = await _audio.listOwn(userId);
    if (listed case Err(:final error)) return Err(_failure(error));
    final removed = await _audio.remove(
      (listed as Ok<List<String>, AudioFailure>).value,
    );
    if (removed case Err(:final error)) return Err(_failure(error));
    final deleted = await _remote.deleteServerData();
    if (deleted is Err) return deleted;

    final audio = [
      for (final row in await (_db.select(
        _db.recordings,
      )..where((t) => t.profileId.equals(userId))).get())
        ?row.audioPath,
    ];
    await _db.transaction(() async {
      for (final synced in syncedTables(_db)) {
        final table = synced.table;
        final idColumn = table.columnsByName['id']! as GeneratedColumn<String>;
        final ids = [
          for (final row
              in await (_db.selectOnly(table)
                    ..addColumns([idColumn])
                    ..where(_owned(synced, userId)))
                  .get())
            row.read(idColumn)!,
        ];
        await (_db.delete(_db.outbox)..where(
              (t) =>
                  t.targetTable.equals(table.actualTableName) &
                  t.rowId.isIn(ids),
            ))
            .go();
        await (_db.delete(table)..where((_) => _owned(synced, userId))).go();
      }
      await (_db.delete(
        _db.syncState,
      )..where((t) => t.profileId.equals(userId))).go();
      await (_db.delete(
        _db.devices,
      )..where((t) => t.profileId.equals(userId))).go();
    });
    for (final path in audio) {
      if (await _store.find(path) case final here?) await _store.delete(here);
    }
    return const Ok(null);
  }

  static MyDataFailure _failure(AudioFailure failure) => switch (failure) {
    AudioFailure.network => MyDataFailure.network,
    AudioFailure.refused => MyDataFailure.unknown,
  };
}
