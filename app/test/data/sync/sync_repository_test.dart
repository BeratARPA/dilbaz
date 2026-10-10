import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/device_repository.dart';
import 'package:dilbaz_app/data/sync/sync_remote.dart';
import 'package:dilbaz_app/data/sync/sync_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_sync_server.dart';
import '../../helpers/pack_fixture.dart';

const userId = '11111111-1111-4111-8111-111111111111';
const courseId = 'a1111111-1111-4111-8111-111111111111';

final t0 = DateTime.utc(2026, 10, 1, 9);
DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

/// One installation: its database and its sync, through the fake server.
final class Device {
  new(FakeSyncServer server, {required this.id, DateTime Function()? now})
    : db = memoryDatabase() {
    sync = DriftSyncRepository(
      db,
      server.remoteFor(userId),
      DriftDeviceRepository(db, newId: () => id, platform: () => 'android'),
      now: now ?? () => clock,
    );
  }

  final String id;
  final AppDatabase db;
  late final DriftSyncRepository sync;
  DateTime clock = at(60);

  Future<SyncReport> run() async => switch (await sync.sync(userId)) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError('sync failed: $error'),
  };

  Future<void> queue(String table, String rowId, {String op = 'upsert'}) => db
      .into(db.outbox)
      .insert(OutboxCompanion.insert(targetTable: table, rowId: rowId, op: op));

  Future<void> profile({required DateTime updatedAt, String name = 'A'}) async {
    await db
        .into(db.profiles)
        .insertOnConflictUpdate(
          ProfilesCompanion.insert(
            id: userId,
            displayName: name,
            settings: const Value({'silent_mode': true}),
            updatedAt: Value(updatedAt),
            createdAt: Value(t0),
            pendingPush: const Value(true),
          ),
        );
    await queue('profiles', userId);
  }

  Future<void> course() async {
    await db
        .into(db.courses)
        .insert(
          CoursesCompanion.insert(
            id: courseId,
            profileId: userId,
            l2: 'en',
            pairPack: 'tr-en',
            levelEstimates: const Value({
              'overall': {'low': 2, 'high': 2},
            }),
            updatedAt: Value(t0),
            createdAt: Value(t0),
            pendingPush: const Value(true),
          ),
        );
    await queue('courses', courseId);
  }

  Future<void> card(
    String id, {
    required DateTime? lastReview,
    int reps = 1,
    String itemRef = 'zz.word.bada',
    bool pending = true,
    bool queued = true,
  }) async {
    await db
        .into(db.cards)
        .insertOnConflictUpdate(
          CardsCompanion.insert(
            id: id,
            profileId: userId,
            courseId: courseId,
            itemRef: itemRef,
            mode: 'speak',
            fsrsCardId: 1,
            state: 2,
            stability: const Value(3.25),
            due: at(3 * 24 * 60),
            lastReview: Value(lastReview),
            reps: Value(reps),
            updatedAt: Value(lastReview ?? t0),
            createdAt: Value(t0),
            pendingPush: Value(pending),
          ),
        );
    if (queued) await queue('cards', id);
  }

  Future<void> attempt(String id, {String course = courseId}) async {
    await db
        .into(db.attempts)
        .insert(
          AttemptsCompanion.insert(
            id: id,
            profileId: userId,
            courseId: course,
            deviceId: this.id,
            activity: 'card.produce_speak',
            itemRef: const Value('zz.word.bada'),
            prompt: const {'prompt_l1': 'Bada de.'},
            response: const {'text': 'bada', 'source': 'typed'},
            verdict: const Value('correct'),
            targetOk: const Value(true),
            errorTags: const Value(['zz.form']),
            createdAtClient: t0,
            createdAt: Value(t0),
            pendingPush: const Value(true),
          ),
        );
    await queue('attempts', id, op: 'insert');
  }

  Future<void> item(String id, {required DateTime updatedAt}) async {
    await db
        .into(db.personalItems)
        .insertOnConflictUpdate(
          PersonalItemsCompanion.insert(
            id: id,
            profileId: userId,
            courseId: courseId,
            kind: 'sentence',
            textL2: 'Item $id',
            source: 'gap',
            updatedAt: Value(updatedAt),
            createdAt: Value(t0),
            pendingPush: const Value(true),
          ),
        );
    await queue('personal_items', id);
  }

  Future<List<OutboxEntry>> outbox() => db.select(db.outbox).get();

  Future<CardRow?> cardRow(String id) =>
      (db.select(db.cards)..where((t) => t.id.equals(id))).getSingleOrNull();
}

void main() {
  late FakeSyncServer server;
  final devices = <Device>[];

  Device device(String id, {DateTime Function()? now}) {
    final made = Device(server, id: id, now: now);
    devices.add(made);
    return made;
  }

  setUp(() => server = FakeSyncServer());
  tearDown(() async {
    for (final made in devices) {
      await made.db.close();
    }
    devices.clear();
  });

  test('a push sends each waiting row once, as it is now', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    await phone.card('card-1', lastReview: at(1));
    // Reviewed again before the push: one row, its latest state.
    await phone.card('card-1', lastReview: at(2), reps: 2);
    await phone.attempt('attempt-1');

    final report = await phone.run();

    expect(report.pushed, 4);
    final batch = server.pushes.single.batch;
    expect(batch['device'], {'platform': 'android'});
    final card = (batch['cards']! as List).single as Map<String, Object?>;
    expect(card['reps'], 2);
    expect(card['last_review'], '2026-10-01T09:02:00.000Z');
    expect(card['suspended'], false);
    expect(card['stability'], 3.25);
    expect(card.containsKey('pending_push'), isFalse);
    expect(card.containsKey('server_seq'), isFalse);
    final attempt = (batch['attempts']! as List).single as Map<String, Object?>;
    expect(attempt['prompt'], {'prompt_l1': 'Bada de.'});
    expect(attempt['error_tags'], ['zz.form']);
    expect(attempt['target_ok'], true);
    expect(server.pushes.single.device, 'device-phone');
  });

  test('a pushed row comes back numbered, and nothing waits', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    await phone.card('card-1', lastReview: at(1));
    await phone.attempt('attempt-1');

    await phone.run();

    expect(await phone.outbox(), isEmpty);
    final card = (await phone.cardRow('card-1'))!;
    expect(card.pendingPush, isFalse);
    expect(card.serverSeq, server.table('cards')['card-1']!['server_seq']);
    final attempt = await phone.db.select(phone.db.attempts).getSingle();
    expect(attempt.pendingPush, isFalse);
    expect(attempt.serverSeq, isNotNull);
    final state = await phone.db.select(phone.db.syncState).getSingle();
    expect(state.lastServerSeq, 4);
    expect(state.lastSyncAt, phone.clock);
    final row = await phone.db.select(phone.db.devices).getSingle();
    expect(row.lastSyncAt, phone.clock);
  });

  test('another device brings everything down as it was', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    await phone.card('card-1', lastReview: at(1));
    await phone.attempt('attempt-1');
    await phone.run();

    final laptop = device('device-laptop');
    final report = await laptop.run();

    expect(report, (pushed: 0, pulled: 4));
    final db = laptop.db;
    final profile = await db.select(db.profiles).getSingle();
    expect(profile.settings, {'silent_mode': true});
    expect(profile.pendingPush, isFalse);
    final course = await db.select(db.courses).getSingle();
    expect(course.levelEstimates, {
      'overall': {'low': 2, 'high': 2},
    });
    final card = (await laptop.cardRow('card-1'))!;
    final original = (await phone.cardRow('card-1'))!;
    expect(card, original);
    expect(card.due.isUtc, isTrue);
    final attempt = await db.select(db.attempts).getSingle();
    expect(attempt.prompt, {'prompt_l1': 'Bada de.'});
    expect(attempt.errorTags, ['zz.form']);
    expect(attempt.targetOk, isTrue);
    expect(attempt.deviceId, 'device-phone');
    expect(await laptop.outbox(), isEmpty);
  });

  test('a later local change waiting to be sent stays; an earlier one gives '
      'way', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    await phone.card('card-1', lastReview: at(1));
    await phone.item('item-1', updatedAt: at(1));
    await phone.run();
    final laptop = device('device-laptop');
    await laptop.run();

    // The phone changes both on the server.
    await phone.card('card-1', lastReview: at(5), reps: 5);
    await phone.item('item-1', updatedAt: at(5));
    await phone.run();
    // The laptop changed them offline, one later and one earlier, and
    // neither could go out yet.
    await laptop.card('card-1', lastReview: at(9), reps: 9);
    await laptop.item('item-1', updatedAt: at(3));
    await laptop.db
        .update(laptop.db.outbox)
        .write(OutboxCompanion(nextAttemptAt: Value(laptop.clock.add(_hour))));

    await laptop.run();

    final card = (await laptop.cardRow('card-1'))!;
    expect((card.reps, card.pendingPush), (9, true));
    final item = await laptop.db.select(laptop.db.personalItems).getSingle();
    expect((item.updatedAt, item.pendingPush), (at(5), false));
    expect(
      [for (final entry in await laptop.outbox()) entry.rowId],
      ['card-1'],
    );
  });

  test('cards of one item made on two devices become one: the later review '
      'wins under the first card', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    await phone.card('card-phone', lastReview: at(1));
    await phone.run();

    final laptop = device('device-laptop');
    await laptop.card('card-laptop', lastReview: at(2), reps: 4);
    await laptop.attempt('attempt-laptop');
    await laptop.run();

    final cards = await laptop.db.select(laptop.db.cards).get();
    expect(cards, hasLength(1));
    expect((cards.single.id, cards.single.reps), ('card-phone', 4));
    expect(cards.single.pendingPush, isTrue);
    expect(
      [for (final entry in await laptop.outbox()) entry.rowId],
      ['card-phone'],
    );

    await laptop.run();
    expect(server.table('cards')['card-phone']!['reps'], 4);
    expect(server.table('cards'), hasLength(1));
    // The attempt keeps the card it was made on (I-03).
    expect(server.table('attempts')['attempt-laptop'], isNotNull);
  });

  test('cards of one item made on two devices become one: an earlier review '
      'gives way', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    await phone.card('card-phone', lastReview: at(5), reps: 5);
    await phone.run();

    final laptop = device('device-laptop');
    await laptop.card('card-laptop', lastReview: at(2), reps: 2);
    await laptop.run();

    final card = await laptop.db.select(laptop.db.cards).getSingle();
    expect((card.id, card.reps, card.pendingPush), ('card-phone', 5, false));
    expect(await laptop.outbox(), isEmpty);
  });

  test('an earlier review of a card gives way to the server', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    await phone.card('card-1', lastReview: at(1));
    await phone.run();
    server.put('cards', {
      ...server.table('cards')['card-1']!,
      'last_review': at(8).toIso8601String(),
      'reps': 8,
    });
    await phone.card('card-1', lastReview: at(4), reps: 4);

    await phone.run();

    expect(server.pushes.last.batch['cards'], isNotEmpty);
    final card = (await phone.cardRow('card-1'))!;
    expect((card.reps, card.pendingPush), (8, false));
    expect(await phone.outbox(), isEmpty);
  });

  test('a row the server refuses waits; the rest goes through', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    await phone.run();
    server
      ..pushes.clear()
      ..refuses = (table, row) => row['id'] == 'item-2';
    for (final id in ['item-1', 'item-2', 'item-3']) {
      await phone.item(id, updatedAt: at(1));
    }

    await phone.run();

    // All three, halves until the refused one is alone.
    expect(server.pushes, hasLength(5));
    expect(server.table('personal_items').keys, {'item-1', 'item-3'});
    final waiting = (await phone.outbox()).single;
    expect(waiting.rowId, 'item-2');
    expect(waiting.attempts, 1);
    expect(waiting.lastError, 'rejected');
    expect(waiting.nextAttemptAt, phone.clock.add(const Duration(minutes: 1)));

    // Not before its time; then again, waiting longer.
    await phone.run();
    expect(server.pushes, hasLength(5));
    phone.clock = phone.clock.add(const Duration(minutes: 1));
    await phone.run();
    expect(server.pushes, hasLength(6));
    final again = (await phone.outbox()).single;
    expect(again.attempts, 2);
    expect(again.nextAttemptAt, phone.clock.add(const Duration(minutes: 2)));
  });

  test('a row of a course the server does not know waits for it', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    await phone.attempt('attempt-1');
    await phone.attempt('attempt-2', course: 'unknown-course');

    await phone.run();

    final waiting = (await phone.outbox()).single;
    expect((waiting.rowId, waiting.lastError), ('attempt-2', 'unknown_course'));
    final attempt = await (phone.db.select(
      phone.db.attempts,
    )..where((t) => t.id.equals('attempt-2'))).getSingle();
    expect(attempt.pendingPush, isTrue);
  });

  test('without a connection nothing changes', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    server.failures.add(SyncFailure.network);

    expect(
      await phone.sync.sync(userId),
      isA<Err<SyncReport, SyncFailure>>().having(
        (e) => e.error,
        'error',
        SyncFailure.network,
      ),
    );
    expect(await phone.outbox(), hasLength(2));
    expect(server.pulls, isEmpty);
    final entry = (await phone.outbox()).first;
    expect((entry.attempts, entry.nextAttemptAt), (0, null));
  });

  test('a pull goes page by page and keeps its cursor', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    for (final id in ['item-1', 'item-2', 'item-3']) {
      await phone.item(id, updatedAt: at(1));
    }
    await phone.run();

    server.pageSize = 2;
    final laptop = device('device-laptop');
    expect((await laptop.run()).pulled, 5);
    expect([for (final pull in server.pulls.skip(1)) pull.since], [0, 2, 4]);
    expect(server.pulls.last.limit, DriftSyncRepository.pullLimit);

    // The next sync starts from the cursor.
    await laptop.run();
    expect(server.pulls.last.since, 5);
  });

  test('a pull failure keeps the pages already taken', () async {
    final phone = device('device-phone');
    await phone.profile(updatedAt: t0);
    await phone.course();
    await phone.item('item-1', updatedAt: at(1));
    await phone.run();

    server.pageSize = 2;
    final laptop = device('device-laptop');
    // The second page fails.
    var calls = 0;
    final failing = _FailingSecondPull(server.remoteFor(userId), () => ++calls);
    final sync = DriftSyncRepository(
      laptop.db,
      failing,
      DriftDeviceRepository(laptop.db, newId: () => 'device-laptop'),
      now: () => laptop.clock,
    );
    expect(await sync.sync(userId), isA<Err<SyncReport, SyncFailure>>());
    final state = await laptop.db.select(laptop.db.syncState).getSingle();
    expect(state.lastServerSeq, 2);
    expect(state.lastSyncAt, isNull);
    expect(await laptop.db.select(laptop.db.profiles).get(), hasLength(1));
  });

  test(
    'entries of rows that are gone go; tables not yet synced wait',
    () async {
      final phone = device('device-phone');
      await phone.queue('cards', 'card-gone');
      await phone.queue('writings', 'writing-1');

      await phone.run();

      expect(server.pushes, isEmpty);
      expect(
        [for (final entry in await phone.outbox()) entry.targetTable],
        ['writings'],
      );
    },
  );

  test('a new outbox entry is heard', () async {
    final phone = device('device-phone');
    final heard = expectLater(phone.sync.watchWaiting(), emits(anything));
    await phone.queue('cards', 'card-1');
    await heard;
  });

  test('the wait after a failure doubles up to an hour', () {
    expect(
      [
        for (final tries in [1, 2, 3, 6, 7, 20])
          DriftSyncRepository.backoff(tries),
      ],
      [
        const Duration(minutes: 1),
        const Duration(minutes: 2),
        const Duration(minutes: 4),
        const Duration(minutes: 32),
        const Duration(hours: 1),
        const Duration(hours: 1),
      ],
    );
  });
}

const _hour = Duration(hours: 1);

/// Passes calls through, but the second pull fails.
final class _FailingSecondPull implements SyncRemote {
  new(this._inner, this._count);

  final SyncRemote _inner;
  final int Function() _count;

  @override
  Future<Result<PushResult, SyncFailure>> push(
    String deviceId,
    Map<String, Object?> batch,
  ) => _inner.push(deviceId, batch);

  @override
  Future<Result<PullPage, SyncFailure>> pull(int since, {required int limit}) {
    if (_count() == 2) return Future.value(const Err(SyncFailure.network));
    return _inner.pull(since, limit: limit);
  }
}
