import 'dart:convert';
import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/tasks/recording_files.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/pack_fixture.dart';

const userId = '11111111-1111-4111-8111-111111111111';
final t0 = DateTime.utc(2026, 10, 8, 9);

void main() {
  late AppDatabase db;
  late FakeRecordingStore store;
  late FakeAudioRemote remote;
  late DriftRecordingFiles files;
  late DateTime now;

  setUp(() {
    db = memoryDatabase();
    store = FakeRecordingStore();
    remote = FakeAudioRemote();
    now = t0;
    files = DriftRecordingFiles(db, store, remote, now: () => now);
  });
  tearDown(() => db.close());

  /// A recording kept here, as the pipeline keeps it.
  Future<String> record(String id) async {
    final audio = (
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'audio/mp4',
      duration: const Duration(seconds: 40),
    );
    await store.save(id, audio);
    final path = recordingStoragePath(
      userId: userId,
      id: id,
      at: now,
      contentType: audio.contentType,
    );
    await DriftRecordingRepository(db, now: () => now).create(
      id: id,
      userId: userId,
      courseId: 'course-1',
      taskRef: 'zz.task.home',
      audioPath: path,
      duration: audio.duration,
      // A test recording: its audio goes up (a task's waits for F3-08).
      isAssessment: true,
    );
    return path;
  }

  Future<List<OutboxEntry>> uploads() async => [
    for (final entry in await db.select(db.outbox).get())
      if (entry.op == DriftRecordingFiles.upload) entry,
  ];

  test("audio waiting goes up once, under the learner's folder", () async {
    final path = await record('rec-1');
    expect(path, '$userId/2026/10/rec-1.m4a');
    expect(await uploads(), hasLength(1));

    expect(await files.uploadWaiting(), 1);

    expect(remote.files[path], [1, 2, 3]);
    expect(await uploads(), isEmpty);
    expect(await files.uploadWaiting(), 0);
  });

  test('without a connection it waits; a refusal waits longer', () async {
    await record('rec-1');
    remote.failure = AudioFailure.network;
    expect(await files.uploadWaiting(), 0);
    expect((await uploads()).single.attempts, 0);

    remote.failure = AudioFailure.refused;
    expect(await files.uploadWaiting(), 0);
    final waiting = (await uploads()).single;
    expect(waiting.attempts, 1);
    expect(waiting.lastError, 'refused');
    expect(waiting.nextAttemptAt, t0.add(const Duration(minutes: 1)));

    // Not before its time.
    remote.failure = null;
    expect(await files.uploadWaiting(), 0);
    now = now.add(const Duration(minutes: 1));
    expect(await files.uploadWaiting(), 1);
  });

  test('audio gone from the device leaves nothing to send', () async {
    await record('rec-1');
    store.files.clear();
    expect(await files.uploadWaiting(), 0);
    expect(await uploads(), isEmpty);
    expect(remote.files, isEmpty);
  });

  test("playing takes this device's audio first, else fetches it", () async {
    final here = await record('rec-1');
    expect(await files.playable(here), '/recordings/rec-1.m4a');

    // Made on another device: it comes down once and is kept.
    const elsewhere = '$userId/2026/09/rec-2.m4a';
    remote.files[elsewhere] = Uint8List.fromList([9]);
    expect(await files.playable(elsewhere), '/recordings/rec-2.m4a');
    expect(store.files['/recordings/rec-2.m4a'], [9]);
    remote.files.clear();
    expect(await files.playable(elsewhere), '/recordings/rec-2.m4a');

    expect(await files.playable('$userId/2026/09/gone.m4a'), isNull);
  });

  group('SupabaseAudioRemote', () {
    SupabaseClient clientWith(MockClientHandler handler) => SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
      httpClient: MockClient(handler),
    );

    test('uploads to the private bucket, replacing', () async {
      late Request seen;
      final remote = SupabaseAudioRemote(
        clientWith((request) async {
          seen = request;
          return Response(
            jsonEncode({'Key': 'audio-private/u/2026/10/r.m4a'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final result = await remote.upload(
        'u/2026/10/r.m4a',
        Uint8List.fromList([1]),
      );
      expect(result, isA<Ok<void, AudioFailure>>());
      expect(seen.url.path, '/storage/v1/object/audio-private/u/2026/10/r.m4a');
      expect(seen.headers['x-upsert'], 'true');
    });

    test('downloads the bytes', () async {
      final remote = SupabaseAudioRemote(
        clientWith(
          (request) async => Response.bytes([7, 8], 200, request: request),
        ),
      );
      final result = await remote.download('u/2026/10/r.m4a');
      expect((result as Ok<Uint8List, AudioFailure>).value, [7, 8]);
    });

    test('no connection, a refusal', () async {
      final offline = SupabaseAudioRemote(
        clientWith((request) async => throw ClientException('offline')),
      );
      expect(
        (await offline.download('x.m4a') as Err).error,
        AudioFailure.network,
      );
      final refused = SupabaseAudioRemote(
        clientWith(
          (request) async => Response(
            jsonEncode({'statusCode': '403', 'error': 'Unauthorized'}),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      expect(
        (await refused.upload('x.m4a', Uint8List(1)) as Err).error,
        AudioFailure.refused,
      );
    });
  });
}
