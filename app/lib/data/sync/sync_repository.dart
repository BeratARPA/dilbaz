import 'dart:math';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:dilbaz_app/data/repositories/device_repository.dart';
import 'package:dilbaz_app/data/sync/sync_remote.dart';
import 'package:dilbaz_app/data/sync/sync_rows.dart';
import 'package:drift/drift.dart';

/// What one sync did: rows sent and rows brought back.
typedef SyncReport = ({int pushed, int pulled});

/// Keeps this device and the server in step (docs/12-architecture.md §6,
/// ADR-0003).
abstract interface class SyncRepository {
  /// Sends what waits in the outbox, then brings what changed on the
  /// server since the last pull.
  Future<Result<SyncReport, SyncFailure>> sync(String userId);

  /// Fires when a local write waits to be sent.
  Stream<void> watchWaiting();
}

/// One row waiting to be sent, with the outbox entries that named it.
typedef _Waiting = ({
  String table,
  String id,
  List<int> entries,
  Map<String, Object?> row,
});

class DriftSyncRepository implements SyncRepository {
  new(this._db, this._remote, this._devices, {this._now = nowUtc});

  final AppDatabase _db;
  final SyncRemote _remote;
  final DeviceRepository _devices;
  final DateTime Function() _now;

  /// At most this many rows go in one push (`sync_push` takes 500).
  static const pushLimit = 500;

  /// Rows asked for in one pull.
  static const pullLimit = 500;

  /// Conflicts the server settles itself: its copy stands, and the next
  /// pull brings it.
  static const _settled = {'stale', 'duplicate'};

  static const _ops = ['insert', 'upsert'];

  late final List<SyncedTable> _tables = syncedTables(_db);

  @override
  Stream<void> watchWaiting() => _db
      .tableUpdates(
        TableUpdateQuery.onTable(
          _db.outbox,
          limitUpdateKind: UpdateKind.insert,
        ),
      )
      .map((_) {});

  @override
  Future<Result<SyncReport, SyncFailure>> sync(String userId) async {
    final deviceId = await _devices.deviceId(userId);
    final pushed = await _push(deviceId);
    if (pushed case Err(:final error)) return Err(error);
    final pulled = await _pull(userId);
    if (pulled case Err(:final error)) return Err(error);
    final now = _now();
    await _db.transaction(() async {
      await (_db.update(_db.devices)..where((t) => t.id.equals(deviceId)))
          .write(DevicesCompanion(lastSyncAt: Value(now)));
      await (_db.update(_db.syncState)
            ..where((t) => t.profileId.equals(userId)))
          .write(SyncStateCompanion(lastSyncAt: Value(now)));
    });
    return Ok((
      pushed: (pushed as Ok<int, SyncFailure>).value,
      pulled: (pulled as Ok<int, SyncFailure>).value,
    ));
  }

  // ---------------------------------------------------------------------
  // Push
  // ---------------------------------------------------------------------

  Future<Result<int, SyncFailure>> _push(String deviceId) async {
    final device = await (_db.select(
      _db.devices,
    )..where((t) => t.id.equals(deviceId))).getSingle();
    var pushed = 0;
    // Every round settles or puts off each entry it read, so it ends.
    for (;;) {
      final due = await _due();
      if (due.isEmpty) return Ok(pushed);
      final rows = await _rows(due);
      if (rows.isEmpty) continue;
      final sent = await _send(deviceId, device.platform, rows);
      switch (sent) {
        case Ok(:final value):
          pushed += value;
        case Err(:final error):
          return Err(error);
      }
    }
  }

  /// Entries of synced tables whose time has come, oldest first.
  Future<List<OutboxEntry>> _due() {
    final names = [for (final synced in _tables) _name(synced)];
    final now = _now();
    return (_db.select(_db.outbox)
          ..where(
            (t) =>
                t.targetTable.isIn(names) &
                t.op.isIn(_ops) &
                (t.nextAttemptAt.isNull() |
                    t.nextAttemptAt.isSmallerOrEqualValue(now)),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.id)])
          ..limit(pushLimit))
        .get();
  }

  /// The rows [due] names, each once, as they are now. Entries of rows that
  /// are gone have nothing to send and are dropped.
  Future<List<_Waiting>> _rows(List<OutboxEntry> due) async {
    final entries = <(String, String), List<int>>{};
    for (final entry in due) {
      entries
          .putIfAbsent((entry.targetTable, entry.rowId), () => [])
          .add(entry.id);
    }
    final rows = <(String, String), Map<String, Object?>>{};
    for (final synced in _tables) {
      final name = _name(synced);
      final ids = [
        for (final (table, id) in entries.keys)
          if (table == name) id,
      ];
      if (ids.isEmpty) continue;
      final found = await (_db.select(
        synced.table,
      )..where((_) => _id(synced).isIn(ids))).get();
      for (final row in found) {
        final server = SyncRows.toServer(synced.table, row! as Insertable);
        rows[(name, server['id']! as String)] = server;
      }
    }
    final gone = [
      for (final MapEntry(:key, :value) in entries.entries)
        if (!rows.containsKey(key)) ...value,
    ];
    if (gone.isNotEmpty) {
      await (_db.delete(_db.outbox)..where((t) => t.id.isIn(gone))).go();
    }
    return [
      for (final MapEntry(:key, :value) in entries.entries)
        if (rows[key] case final row?)
          (table: key.$1, id: key.$2, entries: value, row: row),
    ];
  }

  /// Sends [rows]. A batch the server refuses is halved until the row it
  /// refuses is alone; that row waits and the others go through.
  Future<Result<int, SyncFailure>> _send(
    String deviceId,
    String platform,
    List<_Waiting> rows,
  ) async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      tables.putIfAbsent(row.table, () => []).add(row.row);
    }
    final pushed = await _remote.push(deviceId, {
      'device': {'platform': platform},
      ...tables,
    });
    switch (pushed) {
      case Ok(value: (accepted: _, :final conflicts)):
        await _settle(rows, conflicts);
        return Ok(rows.length);
      case Err(error: SyncFailure.rejected) when rows.length > 1:
        final half = rows.length ~/ 2;
        final first = await _send(deviceId, platform, rows.sublist(0, half));
        if (first case Err()) return first;
        final second = await _send(deviceId, platform, rows.sublist(half));
        if (second case Err()) return second;
        return Ok(
          (first as Ok<int, SyncFailure>).value +
              (second as Ok<int, SyncFailure>).value,
        );
      case Err(error: SyncFailure.rejected):
        await _putOff(rows.single.entries, SyncFailure.rejected.name);
        return const Ok(0);
      case Err(:final error):
        return Err(error);
    }
  }

  /// The server took [rows]: their entries go, except those of rows that
  /// wait for something (an unknown course or attempt). Rows with nothing
  /// left in the outbox are in step.
  Future<void> _settle(List<_Waiting> rows, List<SyncConflict> conflicts) =>
      _db.transaction(() async {
        final waiting = {
          for (final conflict in conflicts)
            if (!_settled.contains(conflict.reason))
              (conflict.table, conflict.id): conflict.reason,
        };
        final done = <_Waiting>[];
        for (final row in rows) {
          if (waiting[(row.table, row.id)] case final reason?) {
            await _putOff(row.entries, reason);
          } else {
            done.add(row);
          }
        }
        await (_db.delete(_db.outbox)..where(
              (t) => t.id.isIn([for (final row in done) ...row.entries]),
            ))
            .go();
        for (final synced in _tables) {
          final name = _name(synced);
          final ids = [
            for (final row in done)
              if (row.table == name) row.id,
          ];
          if (ids.isEmpty) continue;
          await _inStep(synced, ids);
        }
      });

  /// Clears `pending_push` of rows [ids] that nothing waits for anymore.
  Future<void> _inStep(SyncedTable synced, List<String> ids) {
    final id = _id(synced);
    final waiting = _db.selectOnly(_db.outbox)
      ..addColumns([_db.outbox.id])
      ..where(
        _db.outbox.targetTable.equals(_name(synced)) &
            _db.outbox.rowId.equalsExp(id) &
            _db.outbox.op.isIn(_ops),
      );
    return (_db.update(synced.table)
          ..where((_) => id.isIn(ids) & notExistsQuery(waiting)))
        .write(synced.values(const {'pending_push': Variable(false)}));
  }

  /// Tries the entries again later, waiting longer each time.
  Future<void> _putOff(List<int> ids, String code) async {
    final entries = await (_db.select(
      _db.outbox,
    )..where((t) => t.id.isIn(ids))).get();
    for (final entry in entries) {
      final tries = entry.attempts + 1;
      await (_db.update(_db.outbox)..where((t) => t.id.equals(entry.id))).write(
        OutboxCompanion(
          attempts: Value(tries),
          nextAttemptAt: Value(_now().add(backoff(tries))),
          lastError: Value(code),
        ),
      );
    }
  }

  /// 1, 2, 4 … minutes after a failure, at most an hour.
  static Duration backoff(int tries) =>
      Duration(minutes: min(60, 1 << min(tries - 1, 6)));

  // ---------------------------------------------------------------------
  // Pull
  // ---------------------------------------------------------------------

  Future<Result<int, SyncFailure>> _pull(String userId) async {
    final state = await (_db.select(
      _db.syncState,
    )..where((t) => t.profileId.equals(userId))).getSingleOrNull();
    var cursor = state?.lastServerSeq ?? 0;
    var pulled = 0;
    for (;;) {
      final page = await _remote.pull(cursor, limit: pullLimit);
      switch (page) {
        case Err(:final error):
          return Err(error);
        case Ok(value: (:final rows, :final next, :final more)):
          await _db.transaction(() async {
            for (final synced in _tables) {
              for (final row
                  in rows[_name(synced)] ?? const <Map<String, Object?>>[]) {
                await _apply(synced, row);
                pulled++;
              }
            }
            await _db
                .into(_db.syncState)
                .insertOnConflictUpdate(
                  SyncStateCompanion.insert(
                    profileId: userId,
                    lastServerSeq: Value(next),
                  ),
                );
          });
          // A page that moves the cursor no further would never end.
          if (!more || next <= cursor) return Ok(pulled);
          cursor = next;
      }
    }
  }

  /// Takes a server row unless this device's copy is a later change still
  /// to be sent; the server's copy settles what waited to be sent of it.
  Future<void> _apply(SyncedTable synced, Map<String, Object?> row) async {
    final table = synced.table;
    final id = row['id']! as String;
    final local = await (_db.select(
      table,
    )..where((_) => _id(synced).equals(id))).getSingleOrNull();
    if (local == null) {
      if (synced.merge == SyncMerge.lastReview && await _mergeTwin(row)) {
        return;
      }
      await _db
          .into(table)
          .insert(
            synced.values(SyncRows.toLocal(table, row, pending: false)),
            mode: InsertMode.insertOrIgnore,
          );
      return;
    }
    if (_keepsLocal(
      synced.merge,
      (local as Insertable).toColumns(false),
      row,
    )) {
      return;
    }
    await (_db.update(table)..where((_) => _id(synced).equals(id))).write(
      synced.values(SyncRows.toLocal(table, row, pending: false)),
    );
    await _forget(_name(synced), id);
  }

  /// Whether this device's copy is a later change than the server's and
  /// still waits to be sent.
  static bool _keepsLocal(
    SyncMerge merge,
    Map<String, Expression> local,
    Map<String, Object?> server,
  ) {
    if (_value(local['pending_push']) != true) return false;
    return switch (merge) {
      SyncMerge.server => false,
      SyncMerge.updatedAt => _isAfter(
        _value(local['updated_at']) as DateTime?,
        server['updated_at'],
      ),
      SyncMerge.lastReview => _isAfter(
        _value(local['last_review']) as DateTime?,
        server['last_review'],
      ),
    };
  }

  static Object? _value(Expression? column) => switch (column) {
    Variable(:final value) => value,
    _ => null,
  };

  /// Whether [mine] comes after the server time [theirs]; no time is the
  /// earliest.
  static bool _isAfter(DateTime? mine, Object? theirs) {
    if (mine == null) return false;
    if (theirs == null) return true;
    return mine.isAfter(DateTime.parse(theirs as String));
  }

  /// A card of the same item and mode that this device made before the
  /// server's arrived (the server refused it as a duplicate): the two
  /// become the server's card, with the later review's memory. The twin's
  /// attempts keep its id (I-03).
  Future<bool> _mergeTwin(Map<String, Object?> row) async {
    final twin =
        await (_db.select(_db.cards)..where(
              (t) =>
                  t.profileId.equals(row['profile_id']! as String) &
                  t.itemRef.equals(row['item_ref']! as String) &
                  t.mode.equals(row['mode']! as String),
            ))
            .getSingleOrNull();
    if (twin == null) return false;
    final id = row['id']! as String;
    await (_db.delete(_db.cards)..where((t) => t.id.equals(twin.id))).go();
    await _forget(_db.cards.actualTableName, twin.id);
    if (!_isAfter(twin.lastReview, row['last_review'])) {
      await _db
          .into(_db.cards)
          .insert(
            RawValuesInsertable(
              SyncRows.toLocal(_db.cards, row, pending: false),
            ),
          );
      return true;
    }
    // This device's later memory under the server's id, to be sent.
    await _db
        .into(_db.cards)
        .insert(
          twin.copyWith(
            id: id,
            serverSeq: Value(row['server_seq'] as int?),
            pendingPush: true,
          ),
        );
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            targetTable: _db.cards.actualTableName,
            rowId: id,
            op: 'upsert',
          ),
        );
    return true;
  }

  /// Drops what waited to be sent of a row the server's copy settled.
  Future<void> _forget(String table, String id) =>
      (_db.delete(_db.outbox)..where(
            (t) =>
                t.targetTable.equals(table) &
                t.rowId.equals(id) &
                t.op.isIn(_ops),
          ))
          .go();

  static String _name(SyncedTable synced) => synced.table.actualTableName;

  static GeneratedColumn<String> _id(SyncedTable synced) =>
      synced.table.columnsByName['id']! as GeneratedColumn<String>;
}
