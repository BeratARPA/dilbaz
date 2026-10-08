import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:drift/drift.dart';

/// One task of a stored monthly test: what the report compares month by
/// month (docs/06 §3.4).
typedef MonthlyTaskResult = ({
  String taskRef,
  String recordingId,
  bool anchor,

  /// `SpeechMetrics` as stored; null while the recording waits.
  Map<String, Object?>? metrics,

  /// Clauses and error-free clauses, from the marks.
  int? clauses,
  int? errorFree,
});

/// Monthly speaking tests (A23, docs/06-assessment.md §3) and the baseline
/// recording of the placement test (§2 part 4): `assessments` rows of kind
/// `monthly_speaking`, events written once at the end (docs/13 §1).
abstract interface class MonthlyTestRepository {
  /// Whether a monthly test (a baseline does not count) was taken since
  /// [since] (UTC).
  Future<bool> takenSince(String courseId, DateTime since);

  /// The tasks of the latest monthly test before [before], baseline
  /// included; empty before the first.
  Future<List<MonthlyTaskResult>> latestBefore(
    String courseId,
    DateTime before,
  );

  Future<void> save({
    required String id,
    required String userId,
    required String courseId,
    required bool baseline,
    required List<MonthlyTaskResult> tasks,
    bool complete = true,
  });
}

class DriftMonthlyTestRepository implements MonthlyTestRepository {
  new(this._db, {this._now = nowUtc});

  final AppDatabase _db;
  final DateTime Function() _now;

  static const _kind = 'monthly_speaking';
  static const _assessments = 'assessments';

  SimpleSelectStatement<$AssessmentsTable, AssessmentRow> _tests(
    String courseId,
  ) => _db.select(_db.assessments)
    ..where((t) => t.courseId.equals(courseId) & t.kind.equals(_kind))
    ..orderBy([
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);

  @override
  Future<bool> takenSince(String courseId, DateTime since) async =>
      (await _tests(courseId).get()).any(
        (row) =>
            !row.createdAt.isBefore(since) && row.results['baseline'] != true,
      );

  @override
  Future<List<MonthlyTaskResult>> latestBefore(
    String courseId,
    DateTime before,
  ) async {
    final row = (await _tests(
      courseId,
    ).get()).where((row) => row.createdAt.isBefore(before)).firstOrNull;
    return switch (row?.results['tasks']) {
      final List<Object?> tasks => [
        for (final task in tasks)
          if (task case {
            'task_ref': final String taskRef,
            'recording_id': final String recordingId,
          })
            (
              taskRef: taskRef,
              recordingId: recordingId,
              anchor: task['anchor'] == true,
              metrics: switch (task['metrics']) {
                final Map<String, Object?> metrics => metrics,
                _ => null,
              },
              clauses: switch (task['clauses']) {
                final int clauses => clauses,
                _ => null,
              },
              errorFree: switch (task['error_free']) {
                final int errorFree => errorFree,
                _ => null,
              },
            ),
      ],
      _ => const [],
    };
  }

  @override
  Future<void> save({
    required String id,
    required String userId,
    required String courseId,
    required bool baseline,
    required List<MonthlyTaskResult> tasks,
    bool complete = true,
  }) => _db.transaction(() async {
    final now = _now();
    await _db
        .into(_db.assessments)
        .insert(
          AssessmentsCompanion.insert(
            id: id,
            profileId: userId,
            courseId: courseId,
            kind: _kind,
            results: {
              'month':
                  '${now.toLocal().year}-'
                  '${now.toLocal().month.toString().padLeft(2, '0')}',
              'baseline': baseline,
              'complete': complete,
              'tasks': [
                for (final task in tasks)
                  {
                    'task_ref': task.taskRef,
                    'recording_id': task.recordingId,
                    'anchor': task.anchor,
                    'metrics': task.metrics,
                    'clauses': task.clauses,
                    'error_free': task.errorFree,
                  },
              ],
            },
            createdAt: Value(now),
            pendingPush: const Value(true),
          ),
        );
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            targetTable: _assessments,
            rowId: id,
            op: 'insert',
          ),
        );
  });
}
