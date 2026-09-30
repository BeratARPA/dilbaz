import 'package:dilbaz_app/core/result.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

part 'team_repository.freezed.dart';

/// Why a team could not be created or joined.
enum TeamFailure { network, inviteNotFound, unknown }

/// The learner's team with their partner (docs/09-ux-motivation.md §7).
@freezed
abstract class Team with _$Team {
  const factory({
    required String id,
    required String name,

    /// The code a partner joins with; known to the one who created the team.
    String? inviteCode,
  }) = _Team;
}

abstract interface class TeamRepository {
  /// Creates a team named [name]; its invite code is made on the server.
  Future<Result<Team, TeamFailure>> create(String name);

  /// Joins the team with [inviteCode].
  Future<Result<Team, TeamFailure>> join(String inviteCode);
}

/// Calls the `create_team` and `join_team` functions
/// (docs/13-data-model.md §4).
class SupabaseTeamRepository implements TeamRepository {
  const new(this._client);

  final SupabaseClient _client;

  @override
  Future<Result<Team, TeamFailure>> create(String name) =>
      _call('create_team', {'p_name': name});

  @override
  Future<Result<Team, TeamFailure>> join(String inviteCode) =>
      _call('join_team', {'p_invite_code': inviteCode});

  Future<Result<Team, TeamFailure>> _call(
    String function,
    Map<String, Object?> params,
  ) async {
    try {
      final team = await _client.rpc<Map<String, dynamic>>(
        function,
        params: params,
      );
      return Ok(
        Team(
          id: team['id'] as String,
          name: team['name'] as String,
          inviteCode: team['invite_code'] as String?,
        ),
      );
    } on PostgrestException catch (error) {
      return Err(teamFailure(error));
    } on ClientException {
      return const Err(TeamFailure.network);
    }
  }
}

/// Maps a refused call; the functions raise `invite_not_found` for a code
/// that opens no team.
TeamFailure teamFailure(PostgrestException error) => switch (error) {
  PostgrestException(message: 'invite_not_found') => TeamFailure.inviteNotFound,
  _ => TeamFailure.unknown,
};
