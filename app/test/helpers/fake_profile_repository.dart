import 'dart:async';

import 'package:dilbaz_app/core/permissions/permission_gateway.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
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

  @override
  Future<StudySettings?> studySettings(String userId) async => _onboarded
      ? (
          l1: 'tr',
          silentMode: silentMode || !audioConsent,
          dailyBudget: dailyBudget,
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
