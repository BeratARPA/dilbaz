import 'dart:async';

import 'package:dilbaz_app/core/result.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// A member of the learner's team, by the name they chose (I-18: nothing
/// more of the partner's profile).
typedef TeamMember = ({String id, String name});

/// The learner's team (docs/09 §7).
typedef TeamView = ({String id, String name, List<TeamMember> members});

/// Where an invitation is (docs/05 §6).
enum InviteState {
  sent('sent'),
  accepted('accepted'),
  declined('declined'),
  cancelled('cancelled');

  new(this.code);

  final String code;
}

/// "Birlikte yapalım mı?": one partner asks the other to talk through a
/// chat card together (A14).
typedef PairInvite = ({
  String id,
  String from,
  String to,
  String? taskRef,
  InviteState state,
  DateTime createdAt,
});

/// Where an information gap session is (A15).
enum PairState {
  invited('invited'),
  active('active'),
  done('done'),
  cancelled('cancelled');

  new(this.code);

  final String code;
}

/// An information gap session (A15, ADR-0012): who plays which role ('a'
/// or 'b'), where it is, and each partner's answer, by profile.
typedef PairSession = ({
  String id,
  String taskRef,
  String createdBy,
  Map<String, String> roles,
  PairState state,
  Map<String, Object?> answers,
  DateTime createdAt,
});

/// Why the Together tab could not reach the server; it is online only.
enum TogetherFailure { network, refused }

/// Teams, invitations and presence, online (F2-07). Invitations reach the
/// partner's app while it is open, and at its next opening (user decision
/// 2026-10-17); presence is who has the app open now.
abstract interface class TogetherRepository {
  /// The learner's team; null without one.
  Future<Result<TeamView?, TogetherFailure>> team();

  /// The latest invitations to or from the learner, newest first, and
  /// every change after.
  Stream<List<PairInvite>> invites();

  /// Invites [to] in [teamId] to chat card [taskRef].
  Future<Result<void, TogetherFailure>> invite({
    required String teamId,
    required String from,
    required String to,
    required String taskRef,
  });

  /// Answers invitation [id]: yes or not now.
  Future<Result<void, TogetherFailure>> answer(String id, {required bool yes});

  /// Takes back invitation [id].
  Future<Result<void, TogetherFailure>> cancel(String id);

  /// The members of [teamId] with the app open now, the learner [self]
  /// included; joining counts the learner in.
  Stream<Set<String>> present({required String teamId, required String self});

  /// The latest information gap sessions of the learner, newest first, and
  /// every change after.
  Stream<List<PairSession>> sessions();

  /// Starts session [id] on task [taskRef] with [partner], the learner in
  /// [role] ('a' or 'b').
  Future<Result<void, TogetherFailure>> startSession({
    required String id,
    required String taskRef,
    required String partner,
    required String role,
  });

  /// Joins the partner's session [id].
  Future<Result<void, TogetherFailure>> joinSession(String id);

  /// The learner's [answer] in session [id]: an option id, or line indices.
  Future<Result<void, TogetherFailure>> answerSession(String id, Object answer);

  /// Leaves session [id] before it is done.
  Future<Result<void, TogetherFailure>> cancelSession(String id);
}

class SupabaseTogetherRepository implements TogetherRepository {
  new(this._client, {this._now = _utcNow, this._newId = _uuidV7});

  final SupabaseClient _client;
  final DateTime Function() _now;
  final String Function() _newId;

  static DateTime _utcNow() => DateTime.now().toUtc();
  static String _uuidV7() => const Uuid().v7();

  static const _invites = 'pair_invites';
  static const _sessions = 'pair_sessions';

  /// How many invitations the tab keeps in view.
  static const latest = 20;

  Future<Result<T, TogetherFailure>> _call<T>(Future<T> Function() call) async {
    try {
      return Ok(await call());
    } on PostgrestException {
      return const Err(TogetherFailure.refused);
    } on AuthException {
      return const Err(TogetherFailure.refused);
    } on ClientException {
      return const Err(TogetherFailure.network);
    }
  }

  @override
  Future<Result<TeamView?, TogetherFailure>> team() => _call(() async {
    final found = await _client.rpc<Object?>('my_team');
    return switch (found) {
      {
        'id': final String id,
        'name': final String name,
        'members': final List<Object?> members,
      } =>
        (
          id: id,
          name: name,
          members: [
            for (final member in members)
              if (member case {
                'id': final String id,
                'name': final String name,
              })
                (id: id, name: name),
          ],
        ),
      _ => null,
    };
  });

  static PairInvite? _invite(Map<String, dynamic> row) => switch (row) {
    {
      'id': final String id,
      'from_profile': final String from,
      'to_profile': final String to,
      'state': final String state,
      'created_at': final String createdAt,
    } =>
      (
        id: id,
        from: from,
        to: to,
        taskRef: row['task_ref'] as String?,
        state: InviteState.values.firstWhere(
          (s) => s.code == state,
          orElse: () => InviteState.cancelled,
        ),
        createdAt: DateTime.parse(createdAt).toUtc(),
      ),
    _ => null,
  };

  @override
  Stream<List<PairInvite>> invites() => _client
      .from(_invites)
      .stream(primaryKey: ['id'])
      .order('created_at')
      .limit(latest)
      .map(
        (rows) =>
            [for (final row in rows) ?_invite(row)]
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  @override
  Future<Result<void, TogetherFailure>> invite({
    required String teamId,
    required String from,
    required String to,
    required String taskRef,
  }) => _call(
    () => _client.from(_invites).insert({
      'id': _newId(),
      'team_id': teamId,
      'from_profile': from,
      'to_profile': to,
      'activity': 'chat',
      'task_ref': taskRef,
    }),
  );

  @override
  Future<Result<void, TogetherFailure>> answer(
    String id, {
    required bool yes,
  }) => _call(
    () => _client
        .from(_invites)
        .update({
          'state': (yes ? InviteState.accepted : InviteState.declined).code,
          'answered_at': _now().toIso8601String(),
        })
        .eq('id', id),
  );

  @override
  Future<Result<void, TogetherFailure>> cancel(String id) => _call(
    () => _client
        .from(_invites)
        .update({
          'state': InviteState.cancelled.code,
          'answered_at': _now().toIso8601String(),
        })
        .eq('id', id),
  );

  @override
  Stream<Set<String>> present({required String teamId, required String self}) {
    late final RealtimeChannel channel;
    final controller = StreamController<Set<String>>(
      onCancel: () => _client.removeChannel(channel),
    );
    void sync() {
      final ids = <String>{};
      for (final state in channel.presenceState()) {
        for (final presence in state.presences) {
          if (presence.payload['profile'] case final String id) ids.add(id);
        }
      }
      if (!controller.isClosed) controller.add(ids);
    }

    channel = _client
        .channel(
          'team:$teamId',
          opts: const RealtimeChannelConfig(private: true),
        )
        .onPresenceSync((_) => sync())
        .subscribe((status, _) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await channel.track({'profile': self});
          }
        });
    return controller.stream;
  }

  static PairSession? _session(Map<String, dynamic> row) => switch (row) {
    {
      'id': final String id,
      'task_ref': final String taskRef,
      'created_by': final String createdBy,
      'roles': final Map<String, dynamic> roles,
      'state': final String state,
      'answers': final Map<String, dynamic> answers,
      'created_at': final String createdAt,
    } =>
      (
        id: id,
        taskRef: taskRef,
        createdBy: createdBy,
        roles: {
          for (final MapEntry(:key, :value) in roles.entries)
            if (value case final String role) key: role,
        },
        state: PairState.values.firstWhere(
          (s) => s.code == state,
          orElse: () => PairState.cancelled,
        ),
        answers: Map<String, Object?>.of(answers),
        createdAt: DateTime.parse(createdAt).toUtc(),
      ),
    _ => null,
  };

  @override
  Stream<List<PairSession>> sessions() => _client
      .from(_sessions)
      .stream(primaryKey: ['id'])
      .order('created_at')
      .limit(latest)
      .map(
        (rows) =>
            [for (final row in rows) ?_session(row)]
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  @override
  Future<Result<void, TogetherFailure>> startSession({
    required String id,
    required String taskRef,
    required String partner,
    required String role,
  }) => _call(
    () => _client.rpc<Object?>(
      'pair_start',
      params: {
        'p_id': id,
        'p_task_ref': taskRef,
        'p_partner': partner,
        'p_role': role,
      },
    ),
  );

  @override
  Future<Result<void, TogetherFailure>> joinSession(String id) =>
      _call(() => _client.rpc<Object?>('pair_join', params: {'p_id': id}));

  @override
  Future<Result<void, TogetherFailure>> answerSession(
    String id,
    Object answer,
  ) => _call(
    () => _client.rpc<Object?>(
      'pair_answer',
      params: {'p_id': id, 'p_answer': answer},
    ),
  );

  @override
  Future<Result<void, TogetherFailure>> cancelSession(String id) =>
      _call(() => _client.rpc<Object?>('pair_cancel', params: {'p_id': id}));
}
