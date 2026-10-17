import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// An information gap task as the learner's own record (A15): one attempt,
/// written once (I-03). Only the learner's own speech is in it, written
/// down; no audio is kept, and the partner never reads it (I-18).
abstract interface class PairTaskRepository {
  /// Records the learner's part of session [sessionId] on [taskRef].
  Future<void> recordTask({
    required String userId,
    required String courseId,
    required String deviceId,
    required String sessionId,
    required String taskRef,
    required String role,
    required Object? answer,
    required String outcome,
    required Map<String, Object?> result,
    required String transcript,
    required Duration spoken,
    required DateTime at,
    Map<String, Object?>? llm,
  });
}

String _uuidV7() => const Uuid().v7();

class DriftPairTaskRepository implements PairTaskRepository {
  new(this._db, {this._now = nowUtc, this._newId = _uuidV7});

  final AppDatabase _db;
  final DateTime Function() _now;
  final String Function() _newId;

  static const activity = 'pair_info_gap';

  @override
  Future<void> recordTask({
    required String userId,
    required String courseId,
    required String deviceId,
    required String sessionId,
    required String taskRef,
    required String role,
    required Object? answer,
    required String outcome,
    required Map<String, Object?> result,
    required String transcript,
    required Duration spoken,
    required DateTime at,
    Map<String, Object?>? llm,
  }) => _db.transaction(() async {
    final id = _newId();
    await _db
        .into(_db.attempts)
        .insert(
          AttemptsCompanion.insert(
            id: id,
            profileId: userId,
            courseId: courseId,
            deviceId: deviceId,
            activity: activity,
            taskRef: Value(taskRef),
            prompt: {'session': sessionId, 'role': role},
            response: {
              'answer': answer,
              'source': 'asr',
              'text': transcript,
              'result': result,
            },
            verdict: Value(outcome),
            llm: Value(llm),
            durationMs: Value(spoken.inMilliseconds),
            createdAtClient: at,
            createdAt: Value(_now()),
            pendingPush: const Value(true),
          ),
        );
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            targetTable: 'attempts',
            rowId: id,
            op: 'insert',
          ),
        );
  });
}
