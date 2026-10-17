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
import 'package:dilbaz_app/features/together/application/together_view.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'together_controller.g.dart';

/// The activity code of a chat card session (A14).
const chatActivity = 'pair_chat';

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
  final here = await ref.watch(presentProvider(team.id, userId).future);
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
