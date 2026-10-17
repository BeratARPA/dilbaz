import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/data/gap/gap_repository.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/data/repositories/session_repository.dart';
import 'package:dilbaz_app/data/repositories/week_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/features/week/application/week_summary.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pack_fixture.dart';

const user = 'user-1';
const course = 'course-1';

void main() {
  late AppDatabase db;
  // A week of the learner: Monday to Monday (UTC instants).
  final start = DateTime.utc(2026, 9, 28);
  final end = DateTime.utc(2026, 10, 5);
  DateTime inWeek(int day, [int hour = 10]) =>
      DateTime.utc(2026, 9, 28 + day, hour);
  final before = DateTime.utc(2026, 9, 23, 10);

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  var ids = 0;
  Future<void> attempt(
    String activity,
    DateTime at, {
    int? rating,
    String? parent,
    String? id,
  }) => db
      .into(db.attempts)
      .insert(
        AttemptsCompanion.insert(
          id: id ?? 'a${ids++}',
          profileId: user,
          courseId: course,
          deviceId: 'device-1',
          activity: activity,
          prompt: const {},
          response: const {},
          createdAtClient: at,
          rating: Value(rating),
          parentAttemptId: Value(parent),
        ),
      );

  test('the week in counts: days, time, cards and every activity', () async {
    final sessions = DriftSessionRepository(db);
    for (final (at, strands) in [
      (inWeek(1), {Strand.language: const Duration(minutes: 12)}),
      (inWeek(1, 18), {Strand.output: const Duration(minutes: 3)}),
      (inWeek(3), {Strand.fluency: const Duration(minutes: 5)}),
      (before, {Strand.language: const Duration(minutes: 30)}),
    ]) {
      await sessions.record(
        userId: user,
        courseId: course,
        deviceId: 'device-1',
        startedAt: at,
        endedAt: at.add(const Duration(minutes: 20)),
        strands: strands,
      );
    }
    // Two items introduced this week (one with a later listening card),
    // one before it.
    for (final (item, mode, at) in [
      ('zz.a', CardMode.speak, inWeek(1)),
      ('zz.a', CardMode.recognizeAudio, inWeek(1)),
      ('zz.b', CardMode.speak, inWeek(2)),
      ('zz.c', CardMode.speak, before),
      ('zz.c', CardMode.cloze, inWeek(2)),
      ('zz.s', CardMode.dictation, inWeek(2)),
    ]) {
      await DriftCardRepository(
        db,
        now: () => at,
      ).introduce(userId: user, courseId: course, itemRef: item, mode: mode);
    }
    for (final (activity, rating) in [
      ('card.produce_speak', 3),
      ('card.produce_speak', 3),
      ('card.recognize_audio', 1),
      ('card.cloze', 2),
      ('card.produce_speak', 3),
      // An unrated try is no review.
      ('card.produce_speak', null),
      ('dictation', 3),
      ('dictation', null),
    ]) {
      await attempt(activity, inWeek(2), rating: rating);
    }
    await attempt('card.produce_speak', before, rating: 3);
    await attempt('shadowing', inWeek(2), id: 'sh1');
    await attempt('shadowing', inWeek(2), parent: 'sh1');
    await attempt('fluency_432', inWeek(3), id: 'f1');
    await attempt('fluency_432', inWeek(3), parent: 'f1');
    await attempt('fluency_432', inWeek(3), parent: 'f1');
    final recordings = DriftRecordingRepository(db, now: () => inWeek(1));
    for (final (id, assessment) in [
      ('r1', false),
      ('r2', false),
      ('m', true),
    ]) {
      await recordings.create(
        id: id,
        userId: user,
        courseId: course,
        taskRef: 'task',
        audioPath: null,
        duration: const Duration(seconds: 70),
        isAssessment: assessment,
      );
    }
    await DriftGapRepository(db, now: () => inWeek(4)).capture(
      userId: user,
      courseId: course,
      l1Text: 'bir şey',
      context: GapContext.daily,
    );
    await DriftGapRepository(db, now: () => before).capture(
      userId: user,
      courseId: course,
      l1Text: 'önceki',
      context: GapContext.daily,
    );

    final week = await DriftWeekRepository(db).week(course, start, end);
    expect(week.days, hasLength(2));
    expect(week.time, {
      Strand.language: const Duration(minutes: 12),
      Strand.output: const Duration(minutes: 3),
      Strand.fluency: const Duration(minutes: 5),
    });
    expect(week.newItems, 2);
    // Five rated card answers, two of them the new items' first cards.
    expect(week.cardReviews, 3);
    expect(week.dictation, 1);
    expect(week.shadowing, 1);
    expect(week.fluency, 1);
    expect(week.speakingTasks, 2);
    expect(week.speaking, const Duration(seconds: 210));
    expect(week.monthly, isTrue);
    expect(week.captures, 1);
  });

  test('an empty week is all zero', () async {
    final week = await DriftWeekRepository(db).week(course, start, end);
    expect(week.days, isEmpty);
    expect(week.time, isEmpty);
    expect(
      (week.cardReviews, week.newItems, week.captures, week.monthly),
      (0, 0, 0, false),
    );
  });

  group('the offer on Today (docs/09 §5.13)', () {
    // 2026-10-04 is a Sunday, 2026-10-05 a Monday (noon UTC is that day
    // in Europe).
    final sunday = DateTime.utc(2026, 10, 4, 12);
    final monday = DateTime.utc(2026, 10, 5, 12);

    test("Sunday: this week's, once something was done", () {
      expect(
        weekSummaryOffer(now: sunday, daysThisWeek: 2, daysLastWeek: 0),
        WeekSummaryOffer.thisWeek,
      );
      expect(
        weekSummaryOffer(now: sunday, daysThisWeek: 0, daysLastWeek: 0),
        isNull,
      );
    });

    test("a new week before anything: last week's, if it had days", () {
      expect(
        weekSummaryOffer(now: monday, daysThisWeek: 0, daysLastWeek: 3),
        WeekSummaryOffer.lastWeek,
      );
      expect(
        weekSummaryOffer(now: monday, daysThisWeek: 1, daysLastWeek: 3),
        isNull,
      );
      expect(
        weekSummaryOffer(now: monday, daysThisWeek: 0, daysLastWeek: 0),
        isNull,
      );
    });
  });
}
