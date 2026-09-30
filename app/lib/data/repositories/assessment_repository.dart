import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// The course a learner studies, as far as assessments need it.
typedef StudiedCourse = ({
  String id,
  String l2,

  /// The level the curriculum works at, self-reported or measured.
  CefrLevel level,
});

/// Assessments of the learner (docs/06-assessment.md). Results are events:
/// written once, never changed (docs/13-data-model.md §1).
abstract interface class AssessmentRepository {
  /// The active course of [userId]; null before the welcome flow.
  Future<StudiedCourse?> course(String userId);

  /// How many placement tests were taken in the course [courseId].
  Future<int> placementsTaken(String courseId);

  /// Whether the course of [userId] has no placement test yet.
  Stream<bool> watchPlacementOpen(String userId);

  /// Records a placement test: its raw [results], the estimates it led to,
  /// and the course's new level estimates and vocabulary size.
  Future<void> savePlacement({
    required String userId,
    required String courseId,
    required Map<String, Object?> results,
    required PlacementOutcome outcome,
    int? vocabulary,
  });
}

String _uuidV7() => const Uuid().v7();

class DriftAssessmentRepository implements AssessmentRepository {
  new(this._db, {this._now = nowUtc, this._newId = _uuidV7});

  final AppDatabase _db;
  final DateTime Function() _now;
  final String Function() _newId;

  static const _placement = 'placement';
  static const _assessments = 'assessments';
  static const _courses = 'courses';

  SimpleSelectStatement<$CoursesTable, CourseRow> _activeCourse(
    String userId,
  ) => _db.select(_db.courses)
    ..where((t) => t.profileId.equals(userId) & t.active.equals(true))
    ..orderBy([(t) => OrderingTerm(expression: t.createdAt)])
    ..limit(1);

  @override
  Future<StudiedCourse?> course(String userId) async {
    final row = await _activeCourse(userId).getSingleOrNull();
    if (row == null) return null;
    return (
      id: row.id,
      l2: row.l2,
      level: switch (row.levelEstimates[PlacementOutcome.overall]) {
        final Map<String, Object?> overall => LevelEstimate.fromJson(
          overall,
        ).reached,
        _ => CefrLevel.a0,
      },
    );
  }

  @override
  Future<int> placementsTaken(String courseId) async {
    final count = _db.assessments.id.count();
    final query = _db.selectOnly(_db.assessments)
      ..addColumns([count])
      ..where(
        _db.assessments.courseId.equals(courseId) &
            _db.assessments.kind.equals(_placement),
      );
    final row = await query.getSingle();
    return row.read<int>(count) ?? 0;
  }

  @override
  Stream<bool> watchPlacementOpen(String userId) {
    final taken = _db.assessments.id.count();
    final query =
        _db.select(_db.courses).join([
            leftOuterJoin(
              _db.assessments,
              _db.assessments.courseId.equalsExp(_db.courses.id) &
                  _db.assessments.kind.equals(_placement),
            ),
          ])
          ..addColumns([taken])
          ..where(
            _db.courses.profileId.equals(userId) &
                _db.courses.active.equals(true),
          )
          ..groupBy([_db.courses.id]);
    return query.watch().map(
      (rows) => rows.isNotEmpty && rows.every((row) => row.read(taken) == 0),
    );
  }

  @override
  Future<void> savePlacement({
    required String userId,
    required String courseId,
    required Map<String, Object?> results,
    required PlacementOutcome outcome,
    int? vocabulary,
  }) async {
    final now = _now();
    final id = _newId();
    final estimates = outcome.toLevelEstimates();
    await _db.transaction(() async {
      await _db
          .into(_db.assessments)
          .insert(
            AssessmentsCompanion.insert(
              id: id,
              profileId: userId,
              courseId: courseId,
              kind: _placement,
              results: results,
              levelEstimates: Value(estimates),
              createdAt: Value(now),
              pendingPush: const Value(true),
            ),
          );
      final course = await (_db.select(
        _db.courses,
      )..where((t) => t.id.equals(courseId))).getSingle();
      await (_db.update(
        _db.courses,
      )..where((t) => t.id.equals(courseId))).write(
        CoursesCompanion(
          // Skills the test did not measure keep what they had.
          levelEstimates: Value({...course.levelEstimates, ...estimates}),
          vocabEstimate: vocabulary == null
              ? const Value.absent()
              : Value(vocabulary),
          updatedAt: Value(now),
          pendingPush: const Value(true),
        ),
      );
      await _db.batch((batch) {
        batch.insertAll(_db.outbox, [
          OutboxCompanion.insert(
            targetTable: _assessments,
            rowId: id,
            op: 'insert',
          ),
          OutboxCompanion.insert(
            targetTable: _courses,
            rowId: courseId,
            op: 'upsert',
          ),
        ]);
      });
    });
  }
}
