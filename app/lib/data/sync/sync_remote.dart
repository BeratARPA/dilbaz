import 'dart:async';

import 'package:dilbaz_app/core/result.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a push or pull did not go through.
enum SyncFailure {
  /// The server could not be reached.
  network,

  /// The server refused a value in the batch (a data or constraint error):
  /// a smaller batch may go through without it.
  rejected,

  /// Anything else, a session that ran out included.
  unknown,
}

/// A row the server did not take as sent; `reason` is the server's code
/// (`unknown_course`, `unknown_attempt`, `stale`, `duplicate`).
typedef SyncConflict = ({String table, String id, String reason});

typedef PushResult = ({int accepted, List<SyncConflict> conflicts});

/// Rows by table, the cursor after them, and whether more wait.
typedef PullPage = ({
  Map<String, List<Map<String, Object?>>> rows,
  int next,
  bool more,
});

/// The sync RPCs (docs/13-data-model.md §5), under the learner's own rights.
abstract interface class SyncRemote {
  /// Sends [batch] (table name → rows, plus `device`) from [deviceId].
  Future<Result<PushResult, SyncFailure>> push(
    String deviceId,
    Map<String, Object?> batch,
  );

  /// The learner's rows changed after [since], at most [limit] of them.
  Future<Result<PullPage, SyncFailure>> pull(int since, {required int limit});
}

class SupabaseSyncRemote implements SyncRemote {
  const new(this._client);

  final SupabaseClient _client;

  /// A batch is small; a call that takes longer than this has gone wrong.
  static const wait = Duration(seconds: 30);

  @override
  Future<Result<PushResult, SyncFailure>> push(
    String deviceId,
    Map<String, Object?> batch,
  ) =>
      _call('sync_push', {'p_device_id': deviceId, 'p_batch': batch}, (result) {
        final conflicts = result['conflicts']! as List<Object?>;
        return (
          accepted: result['accepted']! as int,
          conflicts: [
            for (final conflict in conflicts.cast<Map<String, Object?>>())
              (
                table: conflict['table']! as String,
                id: conflict['id']! as String,
                reason: conflict['reason']! as String,
              ),
          ],
        );
      });

  @override
  Future<Result<PullPage, SyncFailure>> pull(int since, {required int limit}) =>
      _call('sync_pull', {'p_since': since, 'p_limit': limit}, (result) {
        final rows = result['rows']! as Map<String, Object?>;
        return (
          rows: {
            for (final MapEntry(:key, :value) in rows.entries)
              key: (value! as List<Object?>).cast<Map<String, Object?>>(),
          },
          next: result['next']! as int,
          more: result['more']! as bool,
        );
      });

  Future<Result<T, SyncFailure>> _call<T>(
    String function,
    Map<String, Object?> params,
    T Function(Map<String, Object?> result) read,
  ) async {
    try {
      final result = await _client
          .rpc<Map<String, dynamic>>(function, params: params)
          .timeout(wait);
      return Ok(read(result));
    } on PostgrestException catch (error) {
      return Err(syncFailure(error));
    } on ClientException {
      return const Err(SyncFailure.network);
    } on TimeoutException {
      return const Err(SyncFailure.network);
    }
  }
}

/// A refused call: data and constraint errors (SQLSTATE classes 22 and 23)
/// are the batch's; the rest is not.
SyncFailure syncFailure(PostgrestException error) => switch (error.code) {
  final code? when code.startsWith('22') || code.startsWith('23') =>
    SyncFailure.rejected,
  _ => SyncFailure.unknown,
};
