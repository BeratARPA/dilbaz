import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/assessment_repository.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pack_fixture.dart';

const userId = '11111111-1111-4111-8111-111111111111';
final now = DateTime.utc(2026, 10, 1, 9, 30);
final created = DateTime.utc(2026, 9, 30, 18);

void main() {
  late AppDatabase db;
  late DriftAssessmentRepository repository;

  setUp(() {
    db = memoryDatabase();
    var ids = 0;
    repository = DriftAssessmentRepository(
      db,
      now: () => now,
      newId: () => 'assessment-${++ids}',
    );
  });

  tearDown(() => db.close());

  Future<void> course({
    String id = 'course-1',
    String l2 = 'en',
    Map<String, Object?> levels = const {
      'overall': {'low': 2, 'high': 2, 'confidence': 'low', 'source': 'self'},
      'speaking': {'low': 1, 'high': 2, 'confidence': 'medium'},
    },
    bool active = true,
  }) => db
      .into(db.courses)
      .insert(
        CoursesCompanion.insert(
          id: id,
          profileId: userId,
          l2: l2,
          pairPack: 'tr-$l2',
          levelEstimates: Value(levels),
          active: Value(active),
          updatedAt: Value(created),
          createdAt: Value(created),
        ),
      );

  PlacementOutcome outcome() => PlacementOutcome.of(
    fallback: CefrLevel.a2,
    vocabulary: LevelEstimate.at(CefrLevel.a2, source: 'placement'),
    grammar: LevelEstimate.between(
      CefrLevel.a1,
      CefrLevel.a2,
      source: 'placement',
    ),
  );

  Future<void> save() => repository.savePlacement(
    userId: userId,
    courseId: 'course-1',
    results: const {
      'version': 'A',
      'xlex': {'score': 1850},
    },
    outcome: outcome(),
    vocabulary: 1850,
  );

  group('DriftAssessmentRepository.course', () {
    test('no course before the welcome flow', () async {
      expect(await repository.course(userId), isNull);
    });

    test('the active course, at the level it works at', () async {
      // Another language, put aside.
      await course(id: 'old', l2: 'de', active: false);
      await course();

      expect(await repository.course(userId), (
        id: 'course-1',
        l2: 'en',
        level: CefrLevel.a2,
      ));
    });

    test('a course without a level starts at the bottom', () async {
      await course(levels: const {});
      expect((await repository.course(userId))!.level, CefrLevel.a0);
    });
  });

  group('DriftAssessmentRepository placement', () {
    test('is open once there is a course and until a test is saved', () async {
      final seen = <bool>[];
      final subscription = repository
          .watchPlacementOpen(userId)
          .listen(seen.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await course();
      await pumpEventQueue();
      expect(await repository.placementsTaken('course-1'), 0);
      await save();
      await pumpEventQueue();

      expect(seen, [false, true, false]);
      expect(await repository.placementsTaken('course-1'), 1);
    });

    test('other assessments do not count', () async {
      await course();
      await db
          .into(db.assessments)
          .insert(
            AssessmentsCompanion.insert(
              id: 'monthly',
              profileId: userId,
              courseId: 'course-1',
              kind: 'monthly_speaking',
              results: const {},
            ),
          );

      expect(await repository.placementsTaken('course-1'), 0);
      expect(await repository.watchPlacementOpen(userId).first, isTrue);
    });

    test('saves the results once, as they are', () async {
      await course();
      await save();

      final row = await db.select(db.assessments).getSingle();
      expect(row.id, 'assessment-1');
      expect(row.profileId, userId);
      expect(row.courseId, 'course-1');
      expect(row.kind, 'placement');
      expect(row.results, {
        'version': 'A',
        'xlex': {'score': 1850},
      });
      expect(row.levelEstimates, outcome().toLevelEstimates());
      expect(row.createdAt, now);
      expect(row.pendingPush, isTrue);
    });

    test(
      'updates the course and keeps what the test did not measure',
      () async {
        await course();
        await save();

        final row = await db.select(db.courses).getSingle();
        expect(row.levelEstimates.keys, {
          'overall',
          'speaking',
          'vocabulary',
          'grammar',
        });
        expect(row.levelEstimates['overall'], {
          'low': 1.0,
          'high': 1.0,
          'confidence': 'low',
          'source': 'placement',
        });
        expect(row.levelEstimates['speaking'], {
          'low': 1,
          'high': 2,
          'confidence': 'medium',
        });
        expect(row.vocabEstimate, 1850);
        expect(row.updatedAt, now);
        expect(row.createdAt, created);
        expect(row.pendingPush, isTrue);
      },
    );

    test('a test without the vocabulary part leaves its size alone', () async {
      await course();
      await db
          .update(db.courses)
          .write(const CoursesCompanion(vocabEstimate: Value(1200)));

      await repository.savePlacement(
        userId: userId,
        courseId: 'course-1',
        results: const {},
        outcome: outcome(),
      );

      expect((await db.select(db.courses).getSingle()).vocabEstimate, 1200);
    });

    test('queues both rows for the server (docs/12 §6)', () async {
      await course();
      await save();

      final entries = await db.select(db.outbox).get();
      expect(
        [for (final e in entries) (e.targetTable, e.rowId, e.op)],
        [
          ('assessments', 'assessment-1', 'insert'),
          ('courses', 'course-1', 'upsert'),
        ],
      );
    });
  });
}
