import 'dart:async';

import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

void main() {
  late ProviderContainer container;

  tearDown(() => container.dispose());

  /// Starts the gate and lets it settle.
  Future<void> start({
    required FakeAuthRepository auth,
    required FakeProfileRepository profiles,
  }) async {
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
    )..listen(onboardedProvider, (_, _) {});
    await pumpEventQueue();
  }

  AsyncValue<bool?> onboarded() => container.read(onboardedProvider);

  test('a signed-out device knows nothing and asks nothing', () async {
    final profiles = FakeProfileRepository(onServer: true);
    await start(auth: FakeAuthRepository(), profiles: profiles);

    expect(container.read(currentUserIdProvider).value, isNull);
    expect(onboarded().hasValue, isFalse);
    expect(profiles.restores, 0);
  });

  test('a profile finished on this device needs no server', () async {
    final profiles = FakeProfileRepository(onboarded: true)
      ..failure = ProfileFailure.network;
    await start(auth: FakeAuthRepository(signedIn: true), profiles: profiles);

    expect(container.read(currentUserIdProvider).value, FakeAuthRepository.id);
    expect(onboarded().value, isTrue);
    expect(profiles.restores, 0);
  });

  test('a profile made on another device spares the flow', () async {
    final profiles = FakeProfileRepository(onServer: true);
    await start(auth: FakeAuthRepository(signedIn: true), profiles: profiles);

    expect(profiles.restores, 1);
    expect(onboarded().value, isTrue);
  });

  test('without a profile anywhere the flow is due', () async {
    final profiles = FakeProfileRepository();
    await start(auth: FakeAuthRepository(signedIn: true), profiles: profiles);

    expect(profiles.restores, 1);
    expect(onboarded().value, isFalse);
  });

  test('while the server cannot be asked, nothing is decided', () async {
    final profiles = FakeProfileRepository(onServer: true)
      ..failure = ProfileFailure.network;
    await start(auth: FakeAuthRepository(signedIn: true), profiles: profiles);

    // The profile made elsewhere may exist; the flow must not start.
    expect(onboarded(), const AsyncData<bool?>(null));

    profiles.failure = null;
    container.invalidate(onboardedProvider);
    await pumpEventQueue();
    expect(profiles.restores, 2);
    expect(onboarded().value, isTrue);
  });

  test('only a finished save ends the flow', () async {
    final profiles = FakeProfileRepository();
    await start(auth: FakeAuthRepository(signedIn: true), profiles: profiles);

    const answers = OnboardingAnswers(displayName: 'Berat');
    await profiles.create(FakeAuthRepository.id, answers, finished: false);
    await pumpEventQueue();
    expect(onboarded().value, isFalse);

    await profiles.create(FakeAuthRepository.id, answers, finished: true);
    await pumpEventQueue();
    expect(onboarded().value, isTrue);
  });

  group('startSettled', () {
    ProviderContainer containerWith({
      required FakeAuthRepository auth,
      required FakeProfileRepository profiles,
    }) => container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
    );

    test('a signed-out start waits for nothing', () async {
      final profiles = FakeProfileRepository(onServer: true);
      await startSettled(
        containerWith(auth: FakeAuthRepository(), profiles: profiles),
      );
      expect(profiles.restores, 0);
    });

    test('a profile on this device is known before the first page', () async {
      await startSettled(
        containerWith(
          auth: FakeAuthRepository(signedIn: true),
          profiles: FakeProfileRepository(onboarded: true),
        ),
      );
      expect(onboarded(), const AsyncData<bool?>(true));
    });

    test('so is the answer of a quick server', () async {
      await startSettled(
        containerWith(
          auth: FakeAuthRepository(signedIn: true),
          profiles: FakeProfileRepository(),
        ),
      );
      expect(onboarded(), const AsyncData<bool?>(false));
    });

    test('a slow server is not waited for', () async {
      final slow = Completer<void>();
      final profiles = FakeProfileRepository(onServer: true)..slow = slow;
      await startSettled(
        containerWith(
          auth: FakeAuthRepository(signedIn: true),
          profiles: profiles,
        ),
        patience: const Duration(milliseconds: 20),
      );
      expect(onboarded().isLoading, isTrue);

      // The app goes on listening; the answer arrives behind the opening
      // page.
      container.listen(onboardedProvider, (_, _) {});
      slow.complete();
      await pumpEventQueue();
      expect(onboarded().value, isTrue);
    });
  });

  test('signing in and out is followed', () async {
    final auth = FakeAuthRepository();
    final profiles = FakeProfileRepository(onboarded: true);
    await start(auth: auth, profiles: profiles);
    expect(onboarded().hasValue, isFalse);

    await auth.verifyCode(email: 'b@dilbaz.test', code: '123456');
    await pumpEventQueue();
    expect(container.read(currentUserIdProvider).value, FakeAuthRepository.id);
    expect(onboarded(), const AsyncData<bool?>(true));

    await auth.signOut();
    await pumpEventQueue();
    expect(container.read(currentUserIdProvider).value, isNull);
    // Nothing is known about nobody.
    expect(onboarded().isLoading, isTrue);
  });
}
