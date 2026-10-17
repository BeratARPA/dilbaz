import 'package:dilbaz_app/data/tasks/task_content_repository.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'together_view.freezed.dart';

/// What the Together tab shows (docs/09 §5.9, F2-07).
@freezed
sealed class TogetherView with _$TogetherView {
  /// No course or packs on the device yet.
  const factory unavailable() = TogetherUnavailable;

  /// The server cannot be reached: the tab is online only.
  const factory offline() = TogetherOffline;

  /// No team: one is made or joined in the welcome flow.
  const factory noTeam() = TogetherNoTeam;

  /// A team without a partner yet: its invite code brings them.
  const factory alone({required String teamName}) = TogetherAlone;

  /// With a partner: who they are, whether they have the app open, the
  /// chat cards to choose from, and today's invitations.
  const factory ready({
    required String teamId,
    required String self,
    required TeamMember partner,
    required bool partnerHere,
    required List<ChatCard> cards,

    /// The information gap tasks to choose from (A15).
    @Default(<InfoGapTask>[]) List<InfoGapTask> gaps,

    /// Today's session still open: started by either, waiting or under way.
    ({PairSession session, InfoGapTask task})? gap,

    /// The team's week: the shared goal and each one's counts (F2-09);
    /// null when it could not be had.
    TeamWeek? week,

    /// A cheer the partner sent today.
    Cheer? cheer,

    /// An invitation from the partner waiting for an answer.
    ({PairInvite invite, ChatCard card})? incoming,

    /// The learner's own invitation of today, and how it was answered.
    ({PairInvite invite, ChatCard card})? outgoing,

    /// The card the two agreed on today: it is the suggested activity on
    /// both apps (docs/05 §6).
    ChatCard? agreed,
  }) = TogetherReady;
}
