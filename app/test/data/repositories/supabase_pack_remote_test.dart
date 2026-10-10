import 'dart:convert';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/pack_info.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/supabase_pack_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A registry row as PostgREST returns it (docs/13-data-model.md §2.2).
const Map<String, Object?> row = {
  'id': 'en@1',
  'kind': 'target',
  'l2': 'en',
  'l1': null,
  'version': 1,
  'checksum': 'sha256:58aee6e0',
  'storage_path': 'packs/en@1.sqlite',
};

SupabasePackRemote remoteWith(MockClientHandler handler) => SupabasePackRemote(
  SupabaseClient(
    'https://example.supabase.co',
    'sb_publishable_test',
    httpClient: MockClient(handler),
  ),
);

void main() {
  test('reads a registry row', () {
    expect(
      PackInfo.fromJson(row),
      const PackInfo(
        id: 'en@1',
        kind: 'target',
        l2: 'en',
        version: 1,
        checksum: 'sha256:58aee6e0',
        storagePath: 'packs/en@1.sqlite',
      ),
    );
  });

  group('SupabasePackRemote.published', () {
    test('lists the rows the registry shows', () async {
      late Request seen;
      final remote = remoteWith((request) async {
        seen = request;
        return Response(
          jsonEncode([row]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });

      final result = await remote.published();

      expect((result as Ok).value, [PackInfo.fromJson(row)]);
      expect(seen.url.path, '/rest/v1/packs');
    });

    test('no connection is a network failure', () async {
      final remote = remoteWith(
        (request) async => throw ClientException('offline'),
      );
      expect((await remote.published() as Err).error, PackFailure.network);
    });

    test('a server error is an unknown failure', () async {
      final remote = remoteWith(
        (request) async => Response(
          jsonEncode({'message': 'permission denied', 'code': '42501'}),
          403,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      );
      expect((await remote.published() as Err).error, PackFailure.unknown);
    });
  });

  group('SupabasePackRemote.download', () {
    final pack = PackInfo.fromJson(row);

    test('fetches the file from its bucket and path', () async {
      late Request seen;
      final remote = remoteWith((request) async {
        seen = request;
        return Response.bytes([1, 2, 3], 200);
      });

      final result = await remote.download(pack);

      expect((result as Ok).value, [1, 2, 3]);
      expect(seen.url.path, '/storage/v1/object/packs/en@1.sqlite');
    });

    test('a file that is not there is missing', () async {
      final remote = remoteWith(
        (request) async => Response('{"message":"Object not found"}', 400),
      );
      expect((await remote.download(pack) as Err).error, PackFailure.missing);
    });

    test('no connection is a network failure', () async {
      final remote = remoteWith(
        (request) async => throw ClientException('offline'),
      );
      expect((await remote.download(pack) as Err).error, PackFailure.network);
    });
  });

  test('storage paths name the bucket first', () {
    expect(splitStoragePath('packs/en@1.sqlite'), ('packs', 'en@1.sqlite'));
    expect(splitStoragePath('pack-audio/en/1/v1/a.mp3'), (
      'pack-audio',
      'en/1/v1/a.mp3',
    ));
  });

  test('download failures map by status', () {
    PackFailure failure(String? status) =>
        downloadFailure(StorageException('x', statusCode: status));
    expect(failure('404'), PackFailure.missing);
    expect(failure('400'), PackFailure.missing);
    expect(failure('500'), PackFailure.unknown);
    expect(failure('ClientException'), PackFailure.network);
    expect(failure(null), PackFailure.network);
  });
}
