import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_app/data/tasks/task_content_repository.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/data/together/together_providers.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_app/features/sync/application/sync_controller.dart';
import 'package:dilbaz_app/features/together/application/together_view.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'together_controller.g.dart';

/// The activity code of a chat card session (A14).
const chatActivity = 'pair_chat';

/// The activity code of an information gap task (A15).
const pairTaskActivity = 'pair_info_gap';

/// A chat card talked about this lately goes after the others.
const _lately = Duration(days: 7);

/// The learner's team, asked once a screen needs it.
@riverpod
Future<Result<TeamView?, TogetherFailure>> team(Ref ref) =>
    ref.watch(togetherRepositoryProvider).team();

/// The latest invitations to or from the learner, live.
@riverpod
Stream<List<PairInvite>> invites(Ref ref) =>
    ref.watch(togetherRepositoryProvider).invites();

/// The team's week so far (the learner's Monday on); asked again after each
/// sync, which brings the learner's own sessions up. Null when the server
/// cannot be reached.
@riverpod
Future<TeamWeek?> teamWeek(Ref ref, String teamId) async {
  ref.watch(syncControllerProvider.select((status) => status.lastSyncAt));
  final now = ref.watch(clockProvider)();
  final found = await ref
      .watch(togetherRepositoryProvider)
      .week(
        teamId: teamId,
        since: startOfLocalWeek(now),
        offsetMinutes: now.toLocal().timeZoneOffset.inMinutes,
      );
  return switch (found) {
    Ok(:final value) => value,
    Err() => null,
  };
}

/// Cheers to or from the learner, live.
@riverpod
Stream<List<Cheer>> cheers(Ref ref) =>
    ref.watch(togetherRepositoryProvider).cheers();

/// The learner's information gap sessions, live.
@riverpod
Stream<List<PairSession>> pairSessions(Ref ref) =>
    ref.watch(togetherRepositoryProvider).sessions();

/// Who of the team has the app open, live.
@riverpod
Stream<Set<String>> present(Ref ref, String teamId, String self) =>
    ref.watch(togetherRepositoryProvider).present(teamId: teamId, self: self);

/// The Together tab (docs/09 §5.9, F2-07): the partner, whether they are
/// here, the chat cards and today's invitations. Online only.
@riverpod
Future<TogetherView> together(Ref ref) async {
  final userId = ref.watch(authRepositoryProvider).userId;
  if (userId == null) return const TogetherView.unavailable();
  final course = await ref.watch(assessmentRepositoryProvider).course(userId);
  if (course == null) return const TogetherView.unavailable();
  final found = await ref.watch(teamProvider.future);
  final team = switch (found) {
    Ok(:final value) => value,
    Err() => null,
  };
  if (found is Err) return const TogetherView.offline();
  if (team == null) return const TogetherView.noTeam();
  final partner = team.members.where((m) => m.id != userId).firstOrNull;
  if (partner == null) return TogetherView.alone(teamName: team.name);

  final now = ref.watch(clockProvider)();
  final all = await ref.watch(taskContentRepositoryProvider).chatCards();
  final byKey = {for (final card in all) card.key: card};
  final order = chatCardOrder(
    cards: [for (final card in all) (key: card.key, level: card.level)],
    level: course.level,
    talkedLately: await ref
        .watch(sessionRepositoryProvider)
        .tasksSince(course.id, now.subtract(_lately), chatActivity),
  );
  final sessions = ref.watch(sessionRepositoryProvider);
  final gaps = await ref.watch(taskContentRepositoryProvider).infoGaps();
  final gapsByKey = {for (final task in gaps) task.key: task};
  final gapOrder = chatCardOrder(
    cards: [for (final task in gaps) (key: task.key, level: task.level)],
    level: course.level,
    talkedLately: await sessions.tasksSince(
      course.id,
      now.subtract(_lately),
      pairTaskActivity,
    ),
  );
  ({PairSession session, InfoGapTask task})? open;
  for (final session in await ref.watch(pairSessionsProvider.future)) {
    final task = gapsByKey[session.taskRef];
    if (task != null &&
        !session.createdAt.isBefore(startOfLocalDay(now)) &&
        (session.state == PairState.invited ||
            session.state == PairState.active)) {
      open = (session: session, task: task);
      break;
    }
  }
  final here = await ref.watch(presentProvider(team.id, userId).future);
  final week = await ref.watch(teamWeekProvider(team.id).future);
  final cheer = (await ref.watch(cheersProvider.future))
      .where(
        (c) => c.to == userId && !c.createdAt.isBefore(startOfLocalDay(now)),
      )
      .firstOrNull;
  final invites = await ref.watch(invitesProvider.future);
  final today = startOfLocalDay(now);
  ({PairInvite invite, ChatCard card})? first(bool Function(PairInvite) test) {
    for (final invite in invites) {
      final card = byKey[invite.taskRef];
      if (card != null && !invite.createdAt.isBefore(today) && test(invite)) {
        return (invite: invite, card: card);
      }
    }
    return null;
  }

  return TogetherView.ready(
    teamId: team.id,
    self: userId,
    partner: partner,
    partnerHere: here.contains(partner.id),
    cards: [for (final key in order) byKey[key]!],
    gaps: [for (final key in gapOrder) gapsByKey[key]!],
    week: week,
    cheer: cheer,
    gap: open,
    incoming: first((i) => i.to == userId && i.state == InviteState.sent),
    outgoing: first(
      (i) => i.from == userId && i.state != InviteState.cancelled,
    ),
    agreed: first((i) => i.state == InviteState.accepted)?.card,
  );
}

/// What the learner does on the Together tab; kept while the app runs,
/// so a call finishes after its screen is gone.
@Riverpod(keepAlive: true)
class TogetherActions extends _$TogetherActions {
  @override
  TogetherFailure? build() => null;

  TogetherRepository get _repository => ref.read(togetherRepositoryProvider);

  static String _newId() => const Uuid().v7();

  /// Asks the partner to talk through chat card [card] together.
  Future<void> invite(ChatCard card) async {
    final view = ref.read(togetherProvider).value;
    if (view is! TogetherReady) return;
    _settle(
      await _repository.invite(
        teamId: view.teamId,
        from: view.self,
        to: view.partner.id,
        taskRef: card.key,
      ),
    );
  }

  /// Starts information gap task [task] with the partner; the learner
  /// takes role a. Returns the session's id, or null when it could not.
  Future<String?> startGap(InfoGapTask task) async {
    final view = ref.read(togetherProvider).value;
    if (view is! TogetherReady) return null;
    final id = _newId();
    final result = await _repository.startSession(
      id: id,
      taskRef: task.key,
      partner: view.partner.id,
      role: 'a',
    );
    _settle(result);
    return result is Ok ? id : null;
  }

  /// Sends the partner cheer [key] (docs/09 §7).
  Future<bool> cheer(CheerKey key) async {
    final view = ref.read(togetherProvider).value;
    if (view is! TogetherReady) return false;
    final result = await _repository.cheer(
      teamId: view.teamId,
      from: view.self,
      to: view.partner.id,
      key: key,
    );
    _settle(result);
    return result is Ok;
  }

  /// Answers the partner's invitation [invite]: yes or not now.
  Future<void> answer(PairInvite invite, {required bool yes}) async =>
      _settle(await _repository.answer(invite.id, yes: yes));

  /// Takes back the learner's own invitation [invite].
  Future<void> cancel(PairInvite invite) async =>
      _settle(await _repository.cancel(invite.id));

  void _settle(Result<void, TogetherFailure> result) {
    if (!ref.mounted) return;
    state = switch (result) {
      Ok() => null,
      Err(:final error) => error,
    };
  }
}
