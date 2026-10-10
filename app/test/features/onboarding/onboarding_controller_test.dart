import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/team_repository.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_controller.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late FakeTeamRepository teams;
  late FakePermissionGateway permissions;
  late ProviderContainer container;

  setUp(() {
    auth = FakeAuthRepository(signedIn: true);
    profiles = FakeProfileRepository();
    teams = FakeTeamRepository();
    permissions = FakePermissionGateway();
    // Listening keeps the auto-disposed controller alive for the test.
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
        teamRepositoryProvider.overrideWithValue(teams),
        permissionGatewayProvider.overrideWithValue(permissions),
      ],
    )..listen(onboardingControllerProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  OnboardingController controller() =>
      container.read(onboardingControllerProvider.notifier);
  OnboardingState state() => container.read(onboardingControllerProvider);

  /// Walks forwards to [step], giving the one answer the flow insists on.
  void goTo(OnboardingStep step) {
    controller().answer((a) => a.copyWith(displayName: 'Berat'));
    while (state().step != step) {
      controller().next();
    }
  }

  group('steps (docs/09-ux-motivation.md §5.1)', () {
    test('the flow starts at the welcome with nothing answered', () {
      expect(state(), const OnboardingState());
      expect(state().step, OnboardingStep.welcome);
      expect(state().isFirst, isTrue);
    });

    test('next and back walk the steps in order', () {
      controller().next();
      expect(state().step, OnboardingStep.name);
      controller().back();
      expect(state().step, OnboardingStep.welcome);
      controller().back();
      expect(state().step, OnboardingStep.welcome);
    });

    test('only the name is required', () {
      controller().next();
      expect(state().canGoOn, isFalse);
      controller().next();
      expect(state().step, OnboardingStep.name);

      controller().answer((a) => a.copyWith(displayName: '   '));
      controller().next();
      expect(state().step, OnboardingStep.name);

      controller().answer((a) => a.copyWith(displayName: 'Berat'));
      for (final step in OnboardingStep.values.skip(2)) {
        controller().next();
        expect(state().step, step);
      }
      expect(state().isLast, isTrue);
      controller().next();
      expect(state().step, OnboardingStep.level);
    });

    test('going back keeps the answers', () {
      goTo(OnboardingStep.time);
      controller().answer((a) => a.copyWith(timeBudgetMin: 15));
      controller()
        ..back()
        ..back();
      expect(state().step, OnboardingStep.name);
      expect(state().answers.displayName, 'Berat');
      expect(state().answers.timeBudgetMin, 15);
    });
  });

  group('notifications', () {
    test('allowing asks the system and goes on', () async {
      goTo(OnboardingStep.notifications);
      await controller().askNotifications();
      expect(permissions.asked, ['notifications']);
      expect(state().answers.notifications, isTrue);
      expect(state().step, OnboardingStep.partner);
      expect(state().busy, isFalse);
    });

    test('a refusal in the system dialog goes on without them', () async {
      permissions.notifications = false;
      goTo(OnboardingStep.notifications);
      await controller().askNotifications();
      expect(state().answers.notifications, isFalse);
      expect(state().step, OnboardingStep.partner);
    });

    test('"not now" goes on without asking the system', () {
      goTo(OnboardingStep.notifications);
      controller().skipNotifications();
      expect(permissions.asked, isEmpty);
      expect(state().answers.notifications, isFalse);
      expect(state().step, OnboardingStep.partner);
    });
  });

  group('team', () {
    test('creating sends the profile first, then shows the code', () async {
      goTo(OnboardingStep.partner);
      await controller().createTeam('  Biz  ');

      expect(profiles.saved, [(state().answers, false)]);
      expect(profiles.pushes, 1);
      expect(teams.created, ['Biz']);
      expect(
        state().team,
        const Team(id: 'team-1', name: 'Biz', inviteCode: '0A1B2C3D4E'),
      );
      expect(state().teamFailure, isNull);
      expect(state().busy, isFalse);
      expect(state().step, OnboardingStep.partner);
    });

    test('joining with the partner code enters their team', () async {
      goTo(OnboardingStep.partner);
      await controller().joinTeam(' 0a1b2c3d4e ');
      expect(teams.joined, ['0a1b2c3d4e']);
      expect(state().team, const Team(id: 'team-1', name: 'Biz'));
    });

    test('a code that opens no team is reported calmly', () async {
      goTo(OnboardingStep.partner);
      await controller().joinTeam('FFFFFFFFFF');
      expect(state().team, isNull);
      expect(state().teamFailure, TeamFailure.inviteNotFound);
      expect(state().busy, isFalse);

      await controller().joinTeam(FakeTeamRepository.code);
      expect(state().team, isNotNull);
      expect(state().teamFailure, isNull);
    });

    test('a blank name or code asks for nothing', () async {
      goTo(OnboardingStep.partner);
      await controller().createTeam('   ');
      await controller().joinTeam('');
      expect(profiles.saved, isEmpty);
      expect(teams.created, isEmpty);
      expect(state().teamFailure, isNull);
    });

    test('without a connection no team is asked for', () async {
      profiles.failure = ProfileFailure.network;
      goTo(OnboardingStep.partner);
      await controller().createTeam('Biz');
      expect(teams.created, isEmpty);
      expect(state().teamFailure, TeamFailure.network);
      expect(state().busy, isFalse);
    });

    test('a profile the server refuses is no network problem', () async {
      profiles.failure = ProfileFailure.unknown;
      goTo(OnboardingStep.partner);
      await controller().createTeam('Biz');
      expect(state().teamFailure, TeamFailure.unknown);
    });

    test('a failure of the team call is passed on', () async {
      teams.failure = TeamFailure.network;
      goTo(OnboardingStep.partner);
      await controller().createTeam('Biz');
      expect(profiles.pushes, 1);
      expect(state().team, isNull);
      expect(state().teamFailure, TeamFailure.network);
    });

    test('a second request waits for the first', () async {
      goTo(OnboardingStep.partner);
      final first = controller().createTeam('Biz');
      await controller().createTeam('Biz');
      await first;
      expect(teams.created, ['Biz']);
    });

    test('a signed-out learner asks for nothing', () async {
      await auth.signOut();
      await controller().createTeam('Biz');
      expect(profiles.saved, isEmpty);
      expect(teams.created, isEmpty);
    });
  });

  group('audio consent (docs/14-privacy-security.md §4)', () {
    test('consent comes before the microphone permission', () async {
      await controller().setAudioConsent(granted: true);
      expect(permissions.asked, ['microphone']);
      expect(state().answers.audioConsent, isTrue);
      expect(state().answers.microphone, isTrue);
      expect(state().busy, isFalse);
    });

    test('a refused microphone keeps the consent', () async {
      permissions.microphone = false;
      await controller().setAudioConsent(granted: true);
      expect(state().answers.audioConsent, isTrue);
      expect(state().answers.microphone, isFalse);
    });

    test('taking the consent back asks the system nothing', () async {
      await controller().setAudioConsent(granted: true);
      await controller().setAudioConsent(granted: false);
      expect(permissions.asked, ['microphone']);
      expect(state().answers.audioConsent, isFalse);
      expect(state().answers.microphone, isFalse);
    });
  });

  group('finishing', () {
    test('saves the answers as finished and sends them', () async {
      goTo(OnboardingStep.level);
      controller().answer(
        (a) => a.copyWith(level: 'A2', goals: {'travel'}, aiDataConsent: true),
      );
      await controller().finish();

      expect(profiles.saved, [
        (
          const OnboardingAnswers(
            displayName: 'Berat',
            level: 'A2',
            goals: {'travel'},
            aiDataConsent: true,
          ),
          true,
        ),
      ]);
      expect(profiles.pushes, 1);
      expect(state().busy, isFalse);
    });

    test('offline the flow still ends with the local profile', () async {
      profiles.failure = ProfileFailure.network;
      goTo(OnboardingStep.level);
      await controller().finish();
      expect(profiles.saved.single.$2, isTrue);
      expect(profiles.pushes, 0);
      expect(state().busy, isFalse);
    });

    test('a second tap saves nothing twice', () async {
      goTo(OnboardingStep.level);
      final first = controller().finish();
      await controller().finish();
      await first;
      expect(profiles.saved, hasLength(1));
    });

    test('a signed-out learner saves nothing', () async {
      await auth.signOut();
      await controller().finish();
      expect(profiles.saved, isEmpty);
    });
  });
}
