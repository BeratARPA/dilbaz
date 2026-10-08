import 'dart:convert';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/sync/sync_remote.dart';

/// A server in memory with the rules of `sync_push` and `sync_pull`
/// (supabase/migrations/20261008114210_phase1_sync.sql): enough for devices
/// to sync through it. Rows cross it as JSON, as they would the network.
class FakeSyncServer {
  /// Table → id → row, as the server keeps them.
  final tables = <String, Map<String, Map<String, Object?>>>{};
  final pushes = <({String user, String device, Map<String, Object?> batch})>[];
  final pulls = <({String user, int since, int limit})>[];

  /// The next calls fail with these, then the server answers again.
  final failures = <SyncFailure>[];

  /// Rows the server refuses with a constraint error: the batch fails.
  bool Function(String table, Map<String, Object?> row)? refuses;

  /// Rows in one pull page; the client's limit otherwise.
  int? pageSize;

  var _seq = 0;

  /// Rows of a course: refused when the course is not the caller's.
  static const _ofCourse = {
    'attempts',
    'sessions',
    'assessments',
    'cards',
    'personal_items',
    'gap_entries',
    'recordings',
  };

  SyncRemote remoteFor(String user) => _Remote(this, user);

  Map<String, Map<String, Object?>> table(String name) =>
      tables.putIfAbsent(name, () => {});

  /// Stores [row] as a new version of its id.
  void put(String name, Map<String, Object?> row) {
    table(name)[row['id']! as String] = {...row, 'server_seq': ++_seq};
  }

  Result<PushResult, SyncFailure> _push(
    String user,
    String device,
    Map<String, Object?> sent,
  ) {
    final batch = jsonDecode(jsonEncode(sent)) as Map<String, Object?>;
    pushes.add((user: user, device: device, batch: batch));
    if (failures.isNotEmpty) return Err(failures.removeAt(0));
    List<Map<String, Object?>> rows(String name) =>
        (batch[name] as List<Object?>? ?? const [])
            .cast<Map<String, Object?>>();
    for (final name in batch.keys.where((key) => key != 'device')) {
      if (rows(name).any((row) => refuses?.call(name, row) ?? false)) {
        return const Err(SyncFailure.rejected);
      }
    }
    var accepted = 0;
    final conflicts = <SyncConflict>[];
    Map<String, Object?> own(Map<String, Object?> row) => {
      ...row,
      'profile_id': user,
    };

    for (final row in rows('profiles')) {
      final stored = table('profiles')[user];
      if (row['id'] == user && _later(row['updated_at'], stored)) {
        put('profiles', row);
        accepted++;
      }
    }
    for (final row in rows('courses')) {
      final id = row['id']! as String;
      final twin = table('courses').values.any(
        (c) => c['profile_id'] == user && c['l2'] == row['l2'] && c['id'] != id,
      );
      if (twin) {
        conflicts.add((table: 'courses', id: id, reason: 'duplicate'));
      } else if (_later(row['updated_at'], table('courses')[id])) {
        put('courses', own(row));
        accepted++;
      }
    }
    final courses = {
      for (final course in table('courses').values)
        if (course['profile_id'] == user) course['id'],
    };
    bool ofOwnCourse(String name, Map<String, Object?> row) =>
        !_ofCourse.contains(name) || courses.contains(row['course_id']);
    for (final name in _ofCourse) {
      for (final row in rows(name)) {
        if (!ofOwnCourse(name, row)) {
          conflicts.add((
            table: name,
            id: row['id']! as String,
            reason: 'unknown_course',
          ));
        }
      }
    }

    void addOnce(String name, {Map<String, Object?> forced = const {}}) {
      for (final row in rows(name)) {
        if (!ofOwnCourse(name, row) || table(name).containsKey(row['id'])) {
          continue;
        }
        put(name, {...own(row), ...forced});
        accepted++;
      }
    }

    addOnce('attempts');
    for (final row in rows('attempt_amendments')) {
      final id = row['id']! as String;
      final attempt = table('attempts')[row['attempt_id']];
      if (attempt == null || attempt['profile_id'] != user) {
        conflicts.add((
          table: 'attempt_amendments',
          id: id,
          reason: 'unknown_attempt',
        ));
      } else if (!table('attempt_amendments').containsKey(id)) {
        put('attempt_amendments', own(row));
        accepted++;
      }
    }
    addOnce('sessions');
    addOnce('assessments');
    addOnce('content_reports', forced: const {'status': 'open'});

    for (final row in rows('cards')) {
      if (!ofOwnCourse('cards', row)) continue;
      final id = row['id']! as String;
      final stored = table('cards')[id];
      if (stored != null) {
        if (stored['last_review'] == null ||
            (row['last_review'] != null &&
                _notBefore(row['last_review'], stored['last_review']))) {
          put('cards', own(row));
          accepted++;
        } else {
          conflicts.add((table: 'cards', id: id, reason: 'stale'));
        }
      } else if (table('cards').values.any(
        (c) =>
            c['profile_id'] == user &&
            c['item_ref'] == row['item_ref'] &&
            c['mode'] == row['mode'],
      )) {
        conflicts.add((table: 'cards', id: id, reason: 'duplicate'));
      } else {
        put('cards', own(row));
        accepted++;
      }
    }
    for (final name in ['personal_items', 'gap_entries', 'recordings']) {
      for (final row in rows(name)) {
        if (!ofOwnCourse(name, row)) continue;
        if (_later(row['updated_at'], table(name)[row['id']])) {
          put(name, own(row));
          accepted++;
        }
      }
    }
    return Ok((accepted: accepted, conflicts: conflicts));
  }

  Result<PullPage, SyncFailure> _pull(String user, int since, int limit) {
    pulls.add((user: user, since: since, limit: limit));
    if (failures.isNotEmpty) return Err(failures.removeAt(0));
    final changed = [
      for (final MapEntry(key: name, value: rows) in tables.entries)
        for (final row in rows.values)
          if ((row['profile_id'] ?? row['id']) == user &&
              (row['server_seq']! as int) > since)
            (name: name, row: row),
    ]..sort((a, b) => _seqOf(a.row).compareTo(_seqOf(b.row)));
    final size = pageSize ?? limit;
    final page = changed.take(size).toList();
    final byTable = <String, List<Map<String, Object?>>>{};
    for (final (:name, :row) in page) {
      byTable
          .putIfAbsent(name, () => [])
          .add(jsonDecode(jsonEncode(row)) as Map<String, Object?>);
    }
    return Ok((
      rows: byTable,
      next: page.isEmpty ? since : _seqOf(page.last.row),
      more: changed.length > size,
    ));
  }

  static int _seqOf(Map<String, Object?> row) => row['server_seq']! as int;

  /// Whether a row changed at [incoming] replaces [stored] (later or as
  /// late; nothing stored takes anything).
  static bool _later(Object? incoming, Map<String, Object?>? stored) =>
      stored == null || _notBefore(incoming, stored['updated_at']);

  static bool _notBefore(Object? incoming, Object? stored) =>
      !DateTime.parse(incoming! as String)
          .isBefore(DateTime.parse(stored! as String));
}

class _Remote implements SyncRemote {
  new(this._server, this._user);

  final FakeSyncServer _server;
  final String _user;

  @override
  Future<Result<PushResult, SyncFailure>> push(
    String deviceId,
    Map<String, Object?> batch,
  ) async => _server._push(_user, deviceId, batch);

  @override
  Future<Result<PullPage, SyncFailure>> pull(
    int since, {
    required int limit,
  }) async => _server._pull(_user, since, limit);
}
