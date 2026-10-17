import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Study sessions (docs/13-data-model.md §2.4 `sessions`): the time spent
/// and its strands, for the day's budget (I-13) and the week's balance
/// (docs/05 §2). A row is an event: written once, when the session ends.
abstract interface class SessionRepository {
  Future<void> record({
    required String userId,
    required String courseId,
    required String deviceId,
    required DateTime startedAt,
    required DateTime endedAt,
    required Map<Strand, Duration> strands,
    Map<String, Object?>? planned,
    Map<String, Object?>? done,
  });

  /// Time spent since [since], by strand.
  Future<Map<Strand, Duration>> timeSince(String courseId, DateTime since);

  /// The days (local midnights) with a session since [since].
  Future<Set<DateTime>> daysSince(String courseId, DateTime since);

  /// The tasks of [activity] done since [since] (`planned.task`).
  Future<Set<String>> tasksSince(
    String courseId,
    DateTime since,
    String activity,
  );

  /// When the latest session of [userId] began (UTC), and again after
  /// each new one; null before the first.
  Stream<DateTime?> watchLatestStart(String userId);
}

String _uuidV7() => const Uuid().v7();

class DriftSessionRepository implements SessionRepository {
  new(this._db, {this._newId = _uuidV7});

  final AppDatabase _db;
  final String Function() _newId;

  static const _sessions = 'sessions';

  @override
  Future<void> record({
    required String userId,
    required String courseId,
    required String deviceId,
    required DateTime startedAt,
    required DateTime endedAt,
    required Map<Strand, Duration> strands,
    Map<String, Object?>? planned,
    Map<String, Object?>? done,
  }) => _db.transaction(() async {
    final id = _newId();
    final active = strands.values.fold(Duration.zero, (sum, d) => sum + d);
    await _db
        .into(_db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: id,
            profileId: userId,
            courseId: courseId,
            deviceId: deviceId,
            startedAt: startedAt,
            endedAt: Value(endedAt),
            planned: Value(planned),
            done: Value(done),
            activeMs: Value(active.inMilliseconds),
            strandMs: Value({
              for (final MapEntry(:key, :value) in strands.entries)
                key.code: value.inMilliseconds,
            }),
            createdAt: Value(nowUtc()),
            pendingPush: const Value(true),
          ),
        );
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            targetTable: _sessions,
            rowId: id,
            op: 'insert',
          ),
        );
  });

  Future<List<SessionRow>> _since(String courseId, DateTime since) =>
      (_db.select(_db.sessions)..where(
            (t) =>
                t.courseId.equals(courseId) &
                t.startedAt.isBiggerOrEqualValue(since),
          ))
          .get();

  @override
  Future<Map<Strand, Duration>> timeSince(
    String courseId,
    DateTime since,
  ) async {
    final time = <Strand, Duration>{};
    for (final row in await _since(courseId, since)) {
      for (final strand in Strand.values) {
        if (row.strandMs[strand.code] case final num ms) {
          time[strand] =
              (time[strand] ?? Duration.zero) +
              Duration(milliseconds: ms.round());
        }
      }
    }
    return time;
  }

  @override
  Future<Set<DateTime>> daysSince(String courseId, DateTime since) async => {
    for (final row in await _since(courseId, since)) _localDay(row.startedAt),
  };

  @override
  Future<Set<String>> tasksSince(
    String courseId,
    DateTime since,
    String activity,
  ) async => {
    for (final row in await _since(courseId, since))
      if (row.planned
          case {'activity': final String done, 'task': final String task}
          when done == activity)
        task,
  };

  static DateTime _localDay(DateTime instant) {
    final local = instant.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  @override
  Stream<DateTime?> watchLatestStart(String userId) =>
      (_db.select(_db.sessions)
            ..where((t) => t.profileId.equals(userId))
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.startedAt,
                mode: OrderingMode.desc,
              ),
            ])
            ..limit(1))
          .watchSingleOrNull()
          .map((row) => row?.startedAt);
}
