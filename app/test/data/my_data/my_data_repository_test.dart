import 'dart:convert';
import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/my_data/my_data_remote.dart';
import 'package:dilbaz_app/data/my_data/my_data_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_files.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/pack_fixture.dart';

const a = '11111111-1111-4111-8111-111111111111';
const b = '22222222-2222-4222-8222-222222222222';
final t0 = DateTime.utc(2026, 10, 8, 9);

/// The server's `delete_my_data` in memory.
final class FakeMyDataRemote implements MyDataRemote {
  int calls = 0;
  MyDataFailure? failure;

  @override
  Future<Result<void, MyDataFailure>> deleteServerData() async {
    calls++;
    final failure = this.failure;
    return failure == null ? const Ok(null) : Err(failure);
  }
}

void main() {
  late AppDatabase db;
  late FakeAudioRemote audio;
  late FakeMyDataRemote remote;
  late FakeRecordingStore store;
  late DriftMyDataRepository data;

  setUp(() async {
    db = memoryDatabase();
    audio = FakeAudioRemote();
    remote = FakeMyDataRemote();
    store = FakeRecordingStore();
    data = DriftMyDataRepository(db, remote, audio, store);

    Future<void> queue(String table, String id) => db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(targetTable: table, rowId: id, op: 'upsert'),
        );
    for (final user in [a, b]) {
      await db
          .into(db.profiles)
          .insert(ProfilesCompanion.insert(id: user, displayName: user));
      await db
          .into(db.cards)
          .insert(
            CardsCompanion.insert(
              id: 'card-$user',
              profileId: user,
              courseId: 'course-$user',
              itemRef: 'zz.word.bada',
              mode: 'speak',
              fsrsCardId: 1,
              state: 2,
              due: t0,
            ),
          );
      await queue('cards', 'card-$user');
      await db
          .into(db.devices)
          .insert(
            DevicesCompanion.insert(
              id: 'device-$user',
              profileId: user,
              platform: 'android',
            ),
          );
      await db
          .into(db.syncState)
          .insert(SyncStateCompanion.insert(profileId: user));
      audio.files['$user/2026/10/rec.m4a'] = Uint8List(1);
    }
    await db
        .into(db.courses)
        .insert(
          CoursesCompanion.insert(
            id: 'course-$a',
            profileId: a,
            l2: 'zz',
            pairPack: 'qq-zz',
          ),
        );
    await db
        .into(db.recordings)
        .insert(
          RecordingsCompanion.insert(
            id: 'rec-a',
            profileId: a,
            courseId: 'course-$a',
            audioPath: const Value('$a/2026/10/rec-a.m4a'),
            durationMs: 1000,
          ),
        );
    await queue('recordings', 'rec-a');
    store.files['/recordings/rec-a.m4a'] = Uint8List(1);
  });
  tearDown(() => db.close());

  test(
    "an export holds the learner's own rows, as the server keeps them",
    () async {
      final exported = await data.export(a, at: t0);
      expect(exported['format'], DriftMyDataRepository.format);
      expect(exported['exported_at'], '2026-10-08T09:00:00.000Z');
      final tables = exported['tables']! as Map<String, Object?>;
      expect((tables['profiles']! as List).single, containsPair('id', a));
      final card = (tables['cards']! as List).single as Map<String, Object?>;
      expect(card['id'], 'card-$a');
      expect(card['due'], '2026-10-08T09:00:00.000Z');
      expect(
        (tables['recordings']! as List).single,
        containsPair('id', 'rec-a'),
      );
      // It is plain JSON.
      expect(() => jsonEncode(exported), returnsNormally);
    },
  );

  test("deleting all removes the learner's audio, rows and files", () async {
    expect(await data.deleteAll(a), isA<Ok<void, MyDataFailure>>());

    expect(audio.files.keys, ['$b/2026/10/rec.m4a']);
    expect(remote.calls, 1);
    expect(store.files, isEmpty);
    expect([for (final p in await db.select(db.profiles).get()) p.id], [b]);
    expect(
      [for (final c in await db.select(db.cards).get()) c.id],
      ['card-$b'],
    );
    expect(await db.select(db.courses).get(), isEmpty);
    expect(await db.select(db.recordings).get(), isEmpty);
    expect(
      [for (final e in await db.select(db.outbox).get()) e.rowId],
      ['card-$b'],
    );
    expect(
      [for (final s in await db.select(db.syncState).get()) s.profileId],
      [b],
    );
    expect(
      [for (final d in await db.select(db.devices).get()) d.id],
      ['device-$b'],
    );
  });

  test('nothing here goes unless the server part went through', () async {
    audio.failure = AudioFailure.network;
    expect(
      (await data.deleteAll(a) as Err<void, MyDataFailure>).error,
      MyDataFailure.network,
    );
    expect(remote.calls, 0);

    audio.failure = null;
    remote.failure = MyDataFailure.unknown;
    expect(
      (await data.deleteAll(a) as Err<void, MyDataFailure>).error,
      MyDataFailure.unknown,
    );
    expect(await db.select(db.profiles).get(), hasLength(2));
    expect(store.files, hasLength(1));

    audio.failure = AudioFailure.refused;
    expect(
      (await data.deleteAll(a) as Err<void, MyDataFailure>).error,
      MyDataFailure.unknown,
    );
  });

  group('the server side', () {
    SupabaseClient clientWith(MockClientHandler handler) => SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
      httpClient: MockClient(handler),
    );

    Response json(Object? body, Request request, {int status = 200}) =>
        Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );

    test('delete_my_data, and its failures', () async {
      late Request seen;
      final ok = SupabaseMyDataRemote(
        clientWith((request) async {
          seen = request;
          return Response('', 204, request: request);
        }),
      );
      expect(await ok.deleteServerData(), isA<Ok<void, MyDataFailure>>());
      expect(seen.url.path, '/rest/v1/rpc/delete_my_data');

      final offline = SupabaseMyDataRemote(
        clientWith((request) async => throw ClientException('offline')),
      );
      expect(
        (await offline.deleteServerData() as Err).error,
        MyDataFailure.network,
      );
      final refused = SupabaseMyDataRemote(
        clientWith(
          (request) async =>
              json({'message': 'no', 'code': '42501'}, request, status: 403),
        ),
      );
      expect(
        (await refused.deleteServerData() as Err).error,
        MyDataFailure.unknown,
      );
    });

    test(
      "the learner's audio is listed by year and month, then removed",
      () async {
        final listed = <String>[];
        Object? removed;
        final remote = SupabaseAudioRemote(
          clientWith((request) async {
            if (request.url.path.endsWith('/object/list/audio-private')) {
              final prefix =
                  (jsonDecode(request.body) as Map<String, Object?>)['prefix']!
                      as String;
              listed.add(prefix);
              final depth = prefix.split('/').length;
              return json(switch (depth) {
                // Folders have no id.
                1 => [
                  {'name': '2026', 'id': null},
                ],
                2 => [
                  {'name': '09', 'id': null},
                  {'name': '10', 'id': null},
                ],
                _ => [
                  {'name': 'r-$depth.m4a', 'id': 'file-$prefix'},
                ],
              }, request);
            }
            removed = jsonDecode(request.body);
            return json(<Object?>[], request);
          }),
        );

        final own = await remote.listOwn('u');
        expect((own as Ok<List<String>, AudioFailure>).value, [
          'u/2026/09/r-3.m4a',
          'u/2026/10/r-3.m4a',
        ]);
        expect(listed, ['u', 'u/2026', 'u/2026/09', 'u/2026/10']);

        await remote.remove(own.value);
        expect(removed, {
          'prefixes': ['u/2026/09/r-3.m4a', 'u/2026/10/r-3.m4a'],
        });
      },
    );
  });
}
