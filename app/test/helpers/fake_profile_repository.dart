import 'dart:async';

import 'package:dilbaz_app/core/permissions/permission_gateway.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/settings_change.dart';
import 'package:dilbaz_app/data/repositories/team_repository.dart';

/// In-memory profile for widget and controller tests.
class FakeProfileRepository implements ProfileRepository {
  new({this._onboarded = false, this.onServer = false});

  bool _onboarded;
  final _changes = StreamController<bool>.broadcast();

  /// A finished profile waits on the server (made on another device).
  bool onServer;

  /// Failure of the next server calls; null means they work.
  ProfileFailure? failure;

  /// A slow server: while set, [restore] answers only once it completes.
  Completer<void>? slow;

  /// What was saved, with whether the save finished the flow.
  final saved = <(OnboardingAnswers, bool)>[];
  int pushes = 0;
  int restores = 0;

  @override
  Stream<bool> watchOnboarded(String userId) async* {
    yield _onboarded;
    yield* _changes.stream;
  }

  /// Whether the learner consented to recording audio.
  bool audioConsent = true;

  @override
  Stream<bool> watchAudioConsent(String userId) => Stream.value(audioConsent);

  /// Answers are typed by default.
  bool silentMode = false;
  Duration dailyBudget = const Duration(minutes: 30);
  int weeklyDaysGoal = 5;
  String? anchor = 'morning_coffee';

  /// The daily invitation as set; it goes out again on [setInvitation].
  InvitationSettings? invitation;
  final _invitations = StreamController<InvitationSettings?>.broadcast();

  void setInvitation(InvitationSettings? settings) {
    invitation = settings;
    _invitations.add(settings);
  }

  @override
  Stream<InvitationSettings?> watchInvitation(String userId) async* {
    yield invitation;
    yield* _invitations.stream;
  }

  /// The settings as the Settings screen sees them; changes apply to it.
  ProfileSettings settings = (
    timeBudgetMin: 30,
    weeklyDaysGoal: 5,
    anchor: 'morning_coffee',
    anchorTime: '08:30',
    dailyInvitation: false,
    quietHours: null,
    silentMode: false,
    audioConsent: true,
    aiDataConsent: false,
  );
  final changes = <SettingsChange>[];
  final _settings = StreamController<ProfileSettings?>.broadcast();

  @override
  Stream<ProfileSettings?> watchSettings(String userId) async* {
    yield _onboarded ? settings : null;
    yield* _settings.stream;
  }

  @override
  Future<void> changeSettings(String userId, SettingsChange change) async {
    changes.add(change);
    final s = settings;
    settings = switch (change) {
      BudgetChange(:final minutes) => (
        timeBudgetMin: minutes,
        weeklyDaysGoal: s.weeklyDaysGoal,
        anchor: s.anchor,
        anchorTime: s.anchorTime,
        dailyInvitation: s.dailyInvitation,
        quietHours: s.quietHours,
        silentMode: s.silentMode,
        audioConsent: s.audioConsent,
        aiDataConsent: s.aiDataConsent,
      ),
      DaysGoalChange(:final days) => (
        timeBudgetMin: s.timeBudgetMin,
        weeklyDaysGoal: days,
        anchor: s.anchor,
        anchorTime: s.anchorTime,
        dailyInvitation: s.dailyInvitation,
        quietHours: s.quietHours,
        silentMode: s.silentMode,
        audioConsent: s.audioConsent,
        aiDataConsent: s.aiDataConsent,
      ),
      AnchorChange(:final anchor, :final time) => (
        timeBudgetMin: s.timeBudgetMin,
        weeklyDaysGoal: s.weeklyDaysGoal,
        anchor: anchor,
        anchorTime: time,
        dailyInvitation: s.dailyInvitation,
        quietHours: s.quietHours,
        silentMode: s.silentMode,
        audioConsent: s.audioConsent,
        aiDataConsent: s.aiDataConsent,
      ),
      InvitationChange(:final wanted) => (
        timeBudgetMin: s.timeBudgetMin,
        weeklyDaysGoal: s.weeklyDaysGoal,
        anchor: s.anchor,
        anchorTime: s.anchorTime,
        dailyInvitation: wanted,
        quietHours: s.quietHours,
        silentMode: s.silentMode,
        audioConsent: s.audioConsent,
        aiDataConsent: s.aiDataConsent,
      ),
      QuietHoursChange(:final hours) => (
        timeBudgetMin: s.timeBudgetMin,
        weeklyDaysGoal: s.weeklyDaysGoal,
        anchor: s.anchor,
        anchorTime: s.anchorTime,
        dailyInvitation: s.dailyInvitation,
        quietHours: hours,
        silentMode: s.silentMode,
        audioConsent: s.audioConsent,
        aiDataConsent: s.aiDataConsent,
      ),
      SilentModeChange(:final on) => (
        timeBudgetMin: s.timeBudgetMin,
        weeklyDaysGoal: s.weeklyDaysGoal,
        anchor: s.anchor,
        anchorTime: s.anchorTime,
        dailyInvitation: s.dailyInvitation,
        quietHours: s.quietHours,
        silentMode: on,
        audioConsent: s.audioConsent,
        aiDataConsent: s.aiDataConsent,
      ),
      AudioConsentChange(:final granted) => (
        timeBudgetMin: s.timeBudgetMin,
        weeklyDaysGoal: s.weeklyDaysGoal,
        anchor: s.anchor,
        anchorTime: s.anchorTime,
        dailyInvitation: s.dailyInvitation,
        quietHours: s.quietHours,
        silentMode: s.silentMode,
        audioConsent: granted,
        aiDataConsent: s.aiDataConsent,
      ),
      AiDataConsentChange(:final granted) => (
        timeBudgetMin: s.timeBudgetMin,
        weeklyDaysGoal: s.weeklyDaysGoal,
        anchor: s.anchor,
        anchorTime: s.anchorTime,
        dailyInvitation: s.dailyInvitation,
        quietHours: s.quietHours,
        silentMode: s.silentMode,
        audioConsent: s.audioConsent,
        aiDataConsent: granted,
      ),
    };
    _settings.add(settings);
  }

  @override
  Future<StudySettings?> studySettings(String userId) async => _onboarded
      ? (
          l1: 'tr',
          silentMode: silentMode || !audioConsent,
          dailyBudget: dailyBudget,
          weeklyDaysGoal: weeklyDaysGoal,
          anchor: anchor,
          audioConsent: audioConsent,
        )
      : null;

  @override
  Future<Result<bool, ProfileFailure>> restore(String userId) async {
    restores++;
    await slow?.future;
    final failure = this.failure;
    if (failure != null) return Err(failure);
    if (onServer) _set(onboarded: true);
    return Ok(onServer);
  }

  @override
  Future<void> create(
    String userId,
    OnboardingAnswers answers, {
    required bool finished,
  }) async {
    saved.add((answers, finished));
    if (finished) _set(onboarded: true);
  }

  @override
  Future<Result<void, ProfileFailure>> push(String userId) async {
    final failure = this.failure;
    if (failure != null) return Err(failure);
    pushes++;
    return const Ok(null);
  }

  void _set({required bool onboarded}) {
    _onboarded = onboarded;
    _changes.add(onboarded);
  }
}

/// A server that knows one team.
class FakeTeamRepository implements TeamRepository {
  static const code = '0A1B2C3D4E';

  /// Failure of the next calls; null means they work.
  TeamFailure? failure;
  final created = <String>[];
  final joined = <String>[];

  @override
  Future<Result<Team, TeamFailure>> create(String name) async {
    final failure = this.failure;
    if (failure != null) return Err(failure);
    created.add(name);
    return Ok(Team(id: 'team-1', name: name, inviteCode: code));
  }

  @override
  Future<Result<Team, TeamFailure>> join(String inviteCode) async {
    final failure = this.failure;
    if (failure != null) return Err(failure);
    if (inviteCode.toUpperCase() != code) {
      return const Err(TeamFailure.inviteNotFound);
    }
    joined.add(inviteCode);
    return const Ok(Team(id: 'team-1', name: 'Biz'));
  }
}

/// Answers the system permission dialogs.
class FakePermissionGateway implements PermissionGateway {
  new({this.notifications = true, this.microphone = true});

  bool notifications;
  bool microphone;
  final asked = <String>[];

  @override
  Future<bool> requestNotifications() async {
    asked.add('notifications');
    return notifications;
  }

  @override
  Future<bool> requestMicrophone() async {
    asked.add('microphone');
    return microphone;
  }
}
