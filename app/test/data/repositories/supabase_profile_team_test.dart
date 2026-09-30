import 'dart:convert';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/profile_remote.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/team_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const userId = '11111111-1111-4111-8111-111111111111';

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
  group('SupabaseProfileRemote', () {
    test('fetches the profile with its courses', () async {
      final paths = <String>[];
      final remote = SupabaseProfileRemote(
        clientWith((request) async {
          paths.add(request.url.path);
          return request.url.path.endsWith('/profiles')
              ? json([
                  {'id': userId, 'display_name': 'Berat'},
                ], request)
              : json([
                  {'id': 'course-1', 'profile_id': userId},
                ], request);
        }),
      );

      final result = await remote.fetch(userId) as Ok;

      final fetched = result.value as RemoteProfile;
      expect(fetched.profile['display_name'], 'Berat');
      expect(fetched.courses.single['id'], 'course-1');
      expect(paths, ['/rest/v1/profiles', '/rest/v1/courses']);
    });

    test('no profile yet is no failure', () async {
      final remote = SupabaseProfileRemote(
        clientWith((request) async => json(<Object?>[], request)),
      );
      expect((await remote.fetch(userId) as Ok).value, isNull);
    });

    test('upserts the profile, then its courses', () async {
      final sent = <(String, Object?)>[];
      final remote = SupabaseProfileRemote(
        clientWith((request) async {
          sent.add((request.url.path, jsonDecode(request.body)));
          return Response('', 201, request: request);
        }),
      );

      final result = await remote.upsert(
        profile: {'id': userId},
        courses: [
          {'id': 'course-1'},
        ],
      );

      expect(result, isA<Ok<void, ProfileFailure>>());
      expect(
        [for (final (path, _) in sent) path],
        ['/rest/v1/profiles', '/rest/v1/courses'],
      );
      expect(sent[0].$2, {'id': userId});
      expect(sent[1].$2, [
        {'id': 'course-1'},
      ]);
    });

    test('maps no connection and a refusal', () async {
      final offline = SupabaseProfileRemote(
        clientWith((request) async => throw ClientException('offline')),
      );
      expect(
        (await offline.fetch(userId) as Err).error,
        ProfileFailure.network,
      );
      expect(
        (await offline.upsert(profile: {}, courses: []) as Err).error,
        ProfileFailure.network,
      );
      final refused = SupabaseProfileRemote(
        clientWith(
          (request) async => json(
            {'message': 'denied', 'code': '42501'},
            request,
            status: 403,
          ),
        ),
      );
      expect(
        (await refused.fetch(userId) as Err).error,
        ProfileFailure.unknown,
      );
      expect(
        (await refused.upsert(profile: {}, courses: []) as Err).error,
        ProfileFailure.unknown,
      );
    });
  });

  group('SupabaseTeamRepository', () {
    test('creates a team through create_team', () async {
      late Request seen;
      final teams = SupabaseTeamRepository(
        clientWith((request) async {
          seen = request;
          return json({
            'id': 'team-1',
            'name': 'Biz',
            'invite_code': '0A1B2C3D4E',
          }, request);
        }),
      );

      final result = await teams.create('Biz') as Ok;

      expect(
        result.value,
        const Team(id: 'team-1', name: 'Biz', inviteCode: '0A1B2C3D4E'),
      );
      expect(seen.url.path, '/rest/v1/rpc/create_team');
      expect(jsonDecode(seen.body), {'p_name': 'Biz'});
    });

    test('joins a team through join_team', () async {
      late Request seen;
      final teams = SupabaseTeamRepository(
        clientWith((request) async {
          seen = request;
          return json({'id': 'team-1', 'name': 'Biz'}, request);
        }),
      );

      final result = await teams.join('0a1b2c3d4e') as Ok;

      expect(result.value, const Team(id: 'team-1', name: 'Biz'));
      expect(seen.url.path, '/rest/v1/rpc/join_team');
      expect(jsonDecode(seen.body), {'p_invite_code': '0a1b2c3d4e'});
    });

    test('a code that opens no team is its own failure', () async {
      final teams = SupabaseTeamRepository(
        clientWith(
          (request) async => json(
            {'code': 'P0001', 'message': 'invite_not_found'},
            request,
            status: 400,
          ),
        ),
      );
      expect(
        (await teams.join('0000000000') as Err).error,
        TeamFailure.inviteNotFound,
      );
    });

    test('maps no connection and other refusals', () async {
      final offline = SupabaseTeamRepository(
        clientWith((request) async => throw ClientException('offline')),
      );
      expect((await offline.create('Biz') as Err).error, TeamFailure.network);
      expect(
        teamFailure(
          const PostgrestException(
            message: 'team_name_required',
            code: 'P0001',
          ),
        ),
        TeamFailure.unknown,
      );
    });
  });
}
