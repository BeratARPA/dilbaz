import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/team_repository.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'onboarding_controller.g.dart';

/// The welcome flow: collects the answers step by step and saves them as
/// the learner's profile and course (docs/09-ux-motivation.md §5.1).
@riverpod
class OnboardingController extends _$OnboardingController {
  @override
  OnboardingState build() => const OnboardingState();

  /// Changes the answers.
  void answer(OnboardingAnswers Function(OnboardingAnswers) change) =>
      state = state.copyWith(answers: change(state.answers));

  void next() {
    if (!state.canGoOn || state.isLast) return;
    state = state.copyWith(step: OnboardingStep.values[state.step.index + 1]);
  }

  void back() {
    if (state.isFirst) return;
    state = state.copyWith(step: OnboardingStep.values[state.step.index - 1]);
  }

  /// Asks for the notification permission where its reason is on screen,
  /// then goes on whatever the answer.
  Future<void> askNotifications() async {
    state = state.copyWith(busy: true);
    final granted = await ref
        .read(permissionGatewayProvider)
        .requestNotifications();
    if (!ref.mounted) return;
    state = state.copyWith(
      busy: false,
      answers: state.answers.copyWith(notifications: granted),
    );
    next();
  }

  void skipNotifications() {
    answer((a) => a.copyWith(notifications: false));
    next();
  }

  /// Creates the learner's team; a blank name asks for nothing.
  Future<void> createTeam(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _team((teams) => teams.create(trimmed));
  }

  /// Joins the partner's team; a blank code asks for nothing.
  Future<void> joinTeam(String inviteCode) async {
    final trimmed = inviteCode.trim();
    if (trimmed.isEmpty) return;
    await _team((teams) => teams.join(trimmed));
  }

  /// A team needs the profile on the server, so the answers so far are
  /// saved and sent first; the flow itself goes on.
  Future<void> _team(
    Future<Result<Team, TeamFailure>> Function(TeamRepository teams) call,
  ) async {
    final userId = ref.read(authRepositoryProvider).userId;
    if (userId == null || state.busy) return;
    state = state.copyWith(busy: true, teamFailure: null);
    final profiles = ref.read(profileRepositoryProvider);
    await profiles.create(userId, state.answers, finished: false);
    final pushed = await profiles.push(userId);
    if (!ref.mounted) return;
    if (pushed case Err(:final error)) {
      state = state.copyWith(
        busy: false,
        teamFailure: error == ProfileFailure.network
            ? TeamFailure.network
            : TeamFailure.unknown,
      );
      return;
    }
    final result = await call(ref.read(teamRepositoryProvider));
    if (!ref.mounted) return;
    state = switch (result) {
      Ok(:final value) => state.copyWith(busy: false, team: value),
      Err(:final error) => state.copyWith(busy: false, teamFailure: error),
    };
  }

  /// Records the audio consent; giving it also asks for the microphone.
  Future<void> setAudioConsent({required bool granted}) async {
    if (!granted) {
      answer((a) => a.copyWith(audioConsent: false, microphone: false));
      return;
    }
    state = state.copyWith(busy: true);
    final microphone = await ref
        .read(permissionGatewayProvider)
        .requestMicrophone();
    if (!ref.mounted) return;
    state = state.copyWith(
      busy: false,
      answers: state.answers.copyWith(
        audioConsent: true,
        microphone: microphone,
      ),
    );
  }

  /// Saves the answers and ends the flow. Offline the profile waits in the
  /// outbox; the app goes on with the local copy.
  Future<void> finish() async {
    final userId = ref.read(authRepositoryProvider).userId;
    if (userId == null || state.busy) return;
    state = state.copyWith(busy: true);
    final profiles = ref.read(profileRepositoryProvider);
    await profiles.create(userId, state.answers, finished: true);
    await profiles.push(userId);
    if (ref.mounted) state = state.copyWith(busy: false);
  }
}
