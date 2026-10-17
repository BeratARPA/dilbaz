import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// The rounds of 4/3/2 (A12): each an attempt, written once (I-03). The
/// audio is not kept, as with a card's answer; the words and the measures
/// are.
abstract interface class FluencyRepository {
  /// Round [round] (1–3) of a 4/3/2 on [taskRef]; its attempt id. Rounds
  /// 2 and 3 follow [parentAttemptId], the first round's. Without
  /// [transcript] the round could not be written down.
  Future<String> recordRound({
    required String userId,
    required String courseId,
    required String deviceId,
    required String taskRef,
    required int round,
    required Duration limit,
    required Duration duration,
    required DateTime at,
    Transcript? transcript,
    SpeechMetrics? metrics,
    String? parentAttemptId,
  });

  /// The tasks told in a 4/3/2 since [since] (UTC).
  Future<Set<String>> toldSince(String courseId, DateTime since);
}

String _uuidV7() => const Uuid().v7();

class DriftFluencyRepository implements FluencyRepository {
  new(this._db, {this._now = nowUtc, this._newId = _uuidV7});

  final AppDatabase _db;
  final DateTime Function() _now;
  final String Function() _newId;

  static const activity = 'fluency_432';
  static const _attempts = 'attempts';

  @override
  Future<String> recordRound({
    required String userId,
    required String courseId,
    required String deviceId,
    required String taskRef,
    required int round,
    required Duration limit,
    required Duration duration,
    required DateTime at,
    Transcript? transcript,
    SpeechMetrics? metrics,
    String? parentAttemptId,
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
            parentAttemptId: Value(parentAttemptId),
            prompt: {'round': round, 'limit_ms': limit.inMilliseconds},
            response: {
              'source': 'asr',
              'text': ?transcript?.text,
              if (transcript != null)
                'asr': {
                  'provider': transcript.provider,
                  'model': transcript.model,
                },
              'metrics': ?metrics?.toJson(),
            },
            durationMs: Value(duration.inMilliseconds),
            createdAtClient: at,
            createdAt: Value(_now()),
            pendingPush: const Value(true),
          ),
        );
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            targetTable: _attempts,
            rowId: id,
            op: 'insert',
          ),
        );
    return id;
  });

  @override
  Future<Set<String>> toldSince(String courseId, DateTime since) async => {
    for (final row
        in await (_db.select(_db.attempts)..where(
              (t) =>
                  t.courseId.equals(courseId) &
                  t.activity.equals(activity) &
                  t.createdAtClient.isBiggerOrEqualValue(since),
            ))
            .get())
      ?row.taskRef,
  };
}
