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
}
