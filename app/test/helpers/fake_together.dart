import 'dart:async';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';

/// The Together server in memory: a team, its invitations and who is here.
class FakeTogetherRepository implements TogetherRepository {
  new({this.teamView, this.failure});

  /// The learner's team; null for none.
  TeamView? teamView;

  /// Why the calls fail; null means they work.
  TogetherFailure? failure;

  final _invites = <PairInvite>[];
  final _invitesOut = StreamController<List<PairInvite>>.broadcast();
  final _here = StreamController<Set<String>>.broadcast();
  Set<String> here = {};
  var _ids = 0;

  /// What was asked, in order.
  final calls = <String>[];

  /// The time of the next invitation.
  DateTime now = DateTime.utc(2026, 10, 1, 9);

  List<PairInvite> get all => List.unmodifiable(_invites);

  void _publish() => _invitesOut.add([..._invites.reversed]);

  /// An invitation made elsewhere (the partner's app).
  void receive(PairInvite invite) {
    _invites.add(invite);
    _publish();
  }

  /// Members coming and going.
  void setHere(Set<String> ids) {
    here = ids;
    _here.add(ids);
  }

  @override
  Future<Result<TeamView?, TogetherFailure>> team() async {
    final failure = this.failure;
    return failure == null ? Ok(teamView) : Err(failure);
  }

  @override
  Stream<List<PairInvite>> invites() async* {
    yield [..._invites.reversed];
    yield* _invitesOut.stream;
  }

  @override
  Future<Result<void, TogetherFailure>> invite({
    required String teamId,
    required String from,
    required String to,
    required String taskRef,
  }) async {
    calls.add('invite $to $taskRef');
    final failure = this.failure;
    if (failure != null) return Err(failure);
    _invites.add((
      id: 'invite-${_ids++}',
      from: from,
      to: to,
      taskRef: taskRef,
      state: InviteState.sent,
      createdAt: now,
    ));
    _publish();
    return const Ok(null);
  }

  void _set(String id, InviteState state) {
    final i = _invites.indexWhere((invite) => invite.id == id);
    final invite = _invites[i];
    _invites[i] = (
      id: invite.id,
      from: invite.from,
      to: invite.to,
      taskRef: invite.taskRef,
      state: state,
      createdAt: invite.createdAt,
    );
    _publish();
  }

  @override
  Future<Result<void, TogetherFailure>> answer(
    String id, {
    required bool yes,
  }) async {
    calls.add('answer $id $yes');
    final failure = this.failure;
    if (failure != null) return Err(failure);
    _set(id, yes ? InviteState.accepted : InviteState.declined);
    return const Ok(null);
  }

  @override
  Future<Result<void, TogetherFailure>> cancel(String id) async {
    calls.add('cancel $id');
    final failure = this.failure;
    if (failure != null) return Err(failure);
    _set(id, InviteState.cancelled);
    return const Ok(null);
  }

  @override
  Stream<Set<String>> present({
    required String teamId,
    required String self,
  }) async* {
    calls.add('present $teamId');
    yield {...here, self};
    yield* _here.stream.map((ids) => {...ids, self});
  }

  final _sessions = <PairSession>[];
  final _sessionsOut = StreamController<List<PairSession>>.broadcast();

  /// The learner, as the server knows them from the session.
  String self = '11111111-1111-4111-8111-111111111111';

  List<PairSession> get allSessions => List.unmodifiable(_sessions);

  void _publishSessions() => _sessionsOut.add([..._sessions.reversed]);

  /// A session started elsewhere (the partner's app), or changed there.
  void putSession(PairSession session) {
    final i = _sessions.indexWhere((s) => s.id == session.id);
    if (i < 0) {
      _sessions.add(session);
    } else {
      _sessions[i] = session;
    }
    _publishSessions();
  }

  PairSession _with(
    PairSession s, {
    PairState? state,
    Map<String, Object?>? answers,
  }) => (
    id: s.id,
    taskRef: s.taskRef,
    createdBy: s.createdBy,
    roles: s.roles,
    state: state ?? s.state,
    answers: answers ?? s.answers,
    createdAt: s.createdAt,
  );

  @override
  Stream<List<PairSession>> sessions() async* {
    yield [..._sessions.reversed];
    yield* _sessionsOut.stream;
  }

  @override
  Future<Result<void, TogetherFailure>> startSession({
    required String id,
    required String taskRef,
    required String partner,
    required String role,
  }) async {
    calls.add('start $taskRef $role');
    final failure = this.failure;
    if (failure != null) return Err(failure);
    putSession((
      id: id,
      taskRef: taskRef,
      createdBy: self,
      roles: {self: role, partner: role == 'a' ? 'b' : 'a'},
      state: PairState.invited,
      answers: const {},
      createdAt: now,
    ));
    return const Ok(null);
  }

  @override
  Future<Result<void, TogetherFailure>> joinSession(String id) async {
    calls.add('join $id');
    final failure = this.failure;
    if (failure != null) return Err(failure);
    final i = _sessions.indexWhere((s) => s.id == id);
    putSession(_with(_sessions[i], state: PairState.active));
    return const Ok(null);
  }

  @override
  Future<Result<void, TogetherFailure>> answerSession(
    String id,
    Object answer,
  ) async {
    calls.add('answer-session $id');
    final failure = this.failure;
    if (failure != null) return Err(failure);
    final s = _sessions.firstWhere((s) => s.id == id);
    final answers = {...s.answers, self: answer};
    putSession(
      _with(
        s,
        answers: answers,
        state: answers.length == 2 ? PairState.done : s.state,
      ),
    );
    return const Ok(null);
  }

  /// The partner answers in session [id].
  void partnerAnswers(String id, String partner, Object answer) {
    final s = _sessions.firstWhere((s) => s.id == id);
    final answers = {...s.answers, partner: answer};
    putSession(
      _with(
        s,
        answers: answers,
        state: answers.length == 2 ? PairState.done : s.state,
      ),
    );
  }

  @override
  Future<Result<void, TogetherFailure>> cancelSession(String id) async {
    calls.add('cancel-session $id');
    final failure = this.failure;
    if (failure != null) return Err(failure);
    final s = _sessions.firstWhere((s) => s.id == id);
    putSession(_with(s, state: PairState.cancelled));
    return const Ok(null);
  }
}
