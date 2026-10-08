import 'dart:convert';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/sync/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient clientWith(MockClientHandler handler) => SupabaseClient(
  'https://example.supabase.co',
  'sb_publishable_test',
  httpClient: MockClient(handler),
);

Response json(Object? body, Request request, {int status = 200}) => Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
  request: request,
);

void main() {
  test('a push calls sync_push with the device and the batch', () async {
    late Request seen;
    final remote = SupabaseSyncRemote(
      clientWith((request) async {
        seen = request;
        return json({
          'accepted': 2,
          'conflicts': [
            {'table': 'cards', 'id': 'card-1', 'reason': 'stale'},
          ],
        }, request);
      }),
    );

    final result = await remote.push('device-1', {
      'device': {'platform': 'android'},
      'cards': [
        {'id': 'card-1'},
      ],
    });

    expect(seen.url.path, '/rest/v1/rpc/sync_push');
    expect(jsonDecode(seen.body), {
      'p_device_id': 'device-1',
      'p_batch': {
        'device': {'platform': 'android'},
        'cards': [
          {'id': 'card-1'},
        ],
      },
    });
    final pushed = (result as Ok<PushResult, SyncFailure>).value;
    expect(pushed.accepted, 2);
    expect(pushed.conflicts, [(table: 'cards', id: 'card-1', reason: 'stale')]);
  });

  test('a pull calls sync_pull with the cursor and reads the page', () async {
    late Request seen;
    final remote = SupabaseSyncRemote(
      clientWith((request) async {
        seen = request;
        return json({
          'rows': {
            'cards': [
              {'id': 'card-1', 'server_seq': 7},
            ],
          },
          'next': 7,
          'more': true,
        }, request);
      }),
    );

    final result = await remote.pull(3, limit: 500);

    expect(seen.url.path, '/rest/v1/rpc/sync_pull');
    expect(jsonDecode(seen.body), {'p_since': 3, 'p_limit': 500});
    final page = (result as Ok<PullPage, SyncFailure>).value;
    expect(page.rows, {
      'cards': [
        {'id': 'card-1', 'server_seq': 7},
      ],
    });
    expect((page.next, page.more), (7, true));
  });

  test('an empty pull has no rows', () async {
    final remote = SupabaseSyncRemote(
      clientWith(
        (request) async => json({
          'rows': <String, Object?>{},
          'next': 3,
          'more': false,
        }, request),
      ),
    );
    final page = (await remote.pull(3, limit: 500) as Ok).value as PullPage;
    expect(page.rows, isEmpty);
  });

  test('failures: no connection, a refused value, anything else', () async {
    Future<SyncFailure> failure(MockClientHandler handler) async {
      final result = await SupabaseSyncRemote(clientWith(handler))
          .push('device-1', const {});
      return (result as Err<PushResult, SyncFailure>).error;
    }

    Future<Response> refused(Request request, String code) => Future.value(
      json({'message': 'no', 'code': code}, request, status: 400),
    );

    expect(
      await failure((request) async => throw ClientException('offline')),
      SyncFailure.network,
    );
    expect(
      await failure((request) => refused(request, '23514')),
      SyncFailure.rejected,
    );
    expect(
      await failure((request) => refused(request, '22P02')),
      SyncFailure.rejected,
    );
    expect(
      await failure((request) => refused(request, 'PGRST202')),
      SyncFailure.unknown,
    );
    expect(
      await failure((request) => refused(request, '42501')),
      SyncFailure.unknown,
    );
  });
}
