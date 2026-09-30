import 'dart:convert';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/drift_profile_repository.dart';
import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_profile_remote.dart';
import '../../helpers/pack_fixture.dart';

const userId = '11111111-1111-4111-8111-111111111111';
final now = DateTime.utc(2026, 9, 30, 15, 20);

const answers = OnboardingAnswers(
  displayName: '  Berat ',
  goals: {'travel', 'conversation'},
  goalText: ' Toplantıda rahat konuşmak ',
  timeBudgetMin: 15,
  weeklyDaysGoal: 4,
  anchor: 'after_dinner',
  anchorTime: '20:00',
  notifications: true,
  audioConsent: true,
  level: 'A2',
);

void main() {
  late AppDatabase db;
  late FakeProfileRemote remote;
  late DriftProfileRepository repository;

  DriftProfileRepository repositoryOn(AppDatabase database) {
    var ids = 0;
    return DriftProfileRepository(
      database,
      remote,
      now: () => now,
      newId: () => 'course-${++ids}',
    );
  }

  setUp(() {
    db = memoryDatabase();
    remote = FakeProfileRemote();
    repository = repositoryOn(db);
  });

  tearDown(() => db.close());

  Future<ProfileRow> profile([AppDatabase? database]) =>
      (database ?? db).select((database ?? db).profiles).getSingle();
  Future<CourseRow> course([AppDatabase? database]) =>
      (database ?? db).select((database ?? db).courses).getSingle();

  group('DriftProfileRepository.create', () {
    test('writes the profile with the answers of the welcome flow', () async {
      await repository.create(userId, answers);

      final row = await profile();
      expect(row.id, userId);
      expect(row.displayName, 'Berat');
      expect(row.l1, 'tr');
      expect(row.timeBudgetMin, 15);
      expect(row.weeklyDaysGoal, 4);
      expect(row.anchors, [
        {'label': 'after_dinner', 'time': '20:00'},
      ]);
      expect(row.goalText, 'Toplantıda rahat konuşmak');
      expect(row.interests, ['conversation', 'travel']);
      expect(row.updatedAt, now);
      expect(row.pendingPush, isTrue);
    });

    test('records each consent with its time, given or not', () async {
      await repository.create(userId, answers);

      expect((await profile()).settings, {
        'audio_consent': {'granted': true, 'at': '2026-09-30T15:20:00.000Z'},
        'ai_data_consent': {'granted': false, 'at': '2026-09-30T15:20:00.000Z'},
        'daily_invitation': true,
      });
    });

    test('opens the course at the level the learner chose', () async {
      await repository.create(userId, answers);

      final row = await course();
      expect(row.id, 'course-1');
      expect(row.profileId, userId);
      expect(row.l2, 'en');
      expect(row.pairPack, 'tr-en');
      expect(row.levelEstimates, {
        'overall': {'low': 2, 'high': 2, 'confidence': 'low', 'source': 'self'},
      });
      expect(row.pendingPush, isTrue);
    });

    test('queues both rows for the server (docs/12 §6)', () async {
      await repository.create(userId, answers);

      final entries = await db.select(db.outbox).get();
      expect(
        [for (final e in entries) (e.targetTable, e.rowId, e.op)],
        [('profiles', userId, 'upsert'), ('courses', 'course-1', 'upsert')],
      );
    });

    test('an empty goal text is no goal text', () async {
      await repository.create(userId, answers.copyWith(goalText: '   '));
      expect((await profile()).goalText, isNull);
    });

    test('done again, it keeps the course', () async {
      await repository.create(userId, answers);
      await repository.create(userId, answers.copyWith(level: 'B1'));

      expect((await course()).id, 'course-1');
      expect(
        (await course()).levelEstimates['overall'],
        containsPair('low', 3),
      );
    });
  });

  test('watchOnboarded follows the profile', () async {
    final seen = expectLater(
      repository.watchOnboarded(userId),
      emitsInOrder([false, true]),
    );
    await pumpEventQueue();
    await repository.create(userId, answers);
    await seen;
  });

  group('DriftProfileRepository.push', () {
    test('sends the rows with the server column names', () async {
      await repository.create(userId, answers);

      expect(await repository.push(userId), isA<Ok<void, ProfileFailure>>());

      final sent = remote.stored!;
      expect(sent.profile['display_name'], 'Berat');
      expect(sent.profile['time_budget_min'], 15);
      expect(sent.profile['updated_at'], '2026-09-30T15:20:00.000Z');
      expect(sent.courses.single['profile_id'], userId);
      expect(sent.courses.single['pair_pack'], 'tr-en');
      // Plain JSON all the way down.
      expect(() => jsonEncode([sent.profile, sent.courses]), returnsNormally);
    });

    test('once sent, nothing waits any more', () async {
      await repository.create(userId, answers);
      await repository.push(userId);

      expect((await profile()).pendingPush, isFalse);
      expect((await course()).pendingPush, isFalse);
      expect(await db.select(db.outbox).get(), isEmpty);
    });

    test('a failure keeps everything queued', () async {
      await repository.create(userId, answers);
      remote.failure = ProfileFailure.network;

      final result = await repository.push(userId);

      expect((result as Err).error, ProfileFailure.network);
      expect((await profile()).pendingPush, isTrue);
      expect(await db.select(db.outbox).get(), hasLength(2));
    });

    test('without a profile there is nothing to send', () async {
      expect(await repository.push(userId), isA<Ok<void, ProfileFailure>>());
      expect(remote.upserts, 0);
    });
  });

  group('DriftProfileRepository.restore', () {
    test('no profile on the server: the welcome flow is due', () async {
      expect((await repository.restore(userId) as Ok).value, isFalse);
      expect(await db.select(db.profiles).get(), isEmpty);
    });

    test('brings a profile made on another device', () async {
      await repository.create(userId, answers);
      await repository.push(userId);
      final other = memoryDatabase();
      addTearDown(other.close);

      final restored = await repositoryOn(other).restore(userId);

      expect((restored as Ok).value, isTrue);
      final row = await profile(other);
      final original = await profile();
      expect(row.displayName, original.displayName);
      expect(row.anchors, original.anchors);
      expect(row.settings, original.settings);
      expect(row.interests, original.interests);
      expect(row.updatedAt, original.updatedAt);
      expect(row.serverSeq, 41);
      expect(row.pendingPush, isFalse);
      final restoredCourse = await course(other);
      expect(restoredCourse.id, 'course-1');
      expect(restoredCourse.levelEstimates, (await course()).levelEstimates);
      expect(restoredCourse.serverSeq, 42);
      expect(await other.select(other.outbox).get(), isEmpty);
    });

    test('passes on a failure', () async {
      remote.failure = ProfileFailure.network;
      expect(
        (await repository.restore(userId) as Err).error,
        ProfileFailure.network,
      );
    });
  });
}
