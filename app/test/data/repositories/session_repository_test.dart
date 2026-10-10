import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/session_repository.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pack_fixture.dart';

const userId = '0192f5a0-0000-7000-8000-000000000001';
const courseId = '0192f5a0-0000-7000-8000-0000000000c1';

void main() {
  late AppDatabase db;
  late DriftSessionRepository sessions;
  var next = 0;

  setUp(() {
    db = memoryDatabase();
    next = 0;
    sessions = DriftSessionRepository(db, newId: () => 'session-${next++}');
  });
  tearDown(() => db.close());

  Future<void> record(
    DateTime startedAt,
    Map<Strand, Duration> strands, {
    String course = courseId,
  }) => sessions.record(
    userId: userId,
    courseId: course,
    deviceId: 'device-1',
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 20)),
    strands: strands,
  );

  test('the latest session start comes again after each session', () async {
    final seen = <DateTime?>[];
    final sub = sessions.watchLatestStart(userId).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    final first = DateTime.utc(2026, 10, 7, 9);
    final second = DateTime.utc(2026, 10, 8, 9);
    await record(second, {Strand.language: const Duration(minutes: 5)});
    await pumpEventQueue();
    await record(first, {Strand.language: const Duration(minutes: 5)});
    await pumpEventQueue();
    expect(seen.first, isNull);
    expect(seen.last, second);
  });

  test('a session is one row, queued for the server', () async {
    final start = DateTime.utc(2026, 10, 1, 9);
    await sessions.record(
      userId: userId,
      courseId: courseId,
      deviceId: 'device-1',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 12)),
      strands: {
        Strand.language: const Duration(minutes: 6),
        Strand.output: const Duration(minutes: 3),
      },
      planned: {'reviews': 4, 'new': 2},
      done: {'reviewed': 4, 'introduced': 1},
    );

    final row = (await db.select(db.sessions).get()).single;
    expect(row.id, 'session-0');
    expect(row.profileId, userId);
    expect(row.courseId, courseId);
    expect(row.deviceId, 'device-1');
    expect(row.startedAt, start);
    expect(row.endedAt, start.add(const Duration(minutes: 12)));
    // The time on activities, not the time the app was open.
    expect(row.activeMs, const Duration(minutes: 9).inMilliseconds);
    expect(row.strandMs, {'language': 360000, 'output': 180000});
    expect(row.planned, {'reviews': 4, 'new': 2});
    expect(row.done, {'reviewed': 4, 'introduced': 1});
    expect(row.pendingPush, isTrue);
    final outbox = (await db.select(db.outbox).get()).single;
    expect(outbox.targetTable, 'sessions');
    expect(outbox.rowId, 'session-0');
    expect(outbox.op, 'insert');
  });

  test('the time since a moment adds up by strand, per course', () async {
    final day = DateTime.utc(2026, 10);
    await record(day.subtract(const Duration(hours: 1)), {
      Strand.language: const Duration(minutes: 30),
    });
    await record(day.add(const Duration(hours: 8)), {
      Strand.language: const Duration(minutes: 5),
      Strand.fluency: const Duration(minutes: 2),
    });
    await record(day.add(const Duration(hours: 12)), {
      Strand.language: const Duration(minutes: 7),
    });
    await record(day.add(const Duration(hours: 9)), {
      Strand.input: const Duration(minutes: 40),
    }, course: 'another-course');

    expect(await sessions.timeSince(courseId, day), {
      Strand.language: const Duration(minutes: 12),
      Strand.fluency: const Duration(minutes: 2),
    });
    expect(
      await sessions.timeSince(courseId, day.add(const Duration(days: 1))),
      isEmpty,
    );
  });

  test('the days studied are local days, each once', () async {
    final monday = DateTime(2026, 9, 28);
    for (final start in [
      DateTime(2026, 9, 25, 20),
      DateTime(2026, 9, 29, 8),
      DateTime(2026, 9, 29, 21),
      DateTime(2026, 10, 1, 7),
    ]) {
      await record(start.toUtc(), {
        Strand.language: const Duration(minutes: 5),
      });
    }

    expect(await sessions.daysSince(courseId, monday.toUtc()), {
      DateTime(2026, 9, 29),
      DateTime(2026, 10),
    });
  });
}
