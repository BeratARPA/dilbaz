import 'package:dilbaz_app/data/repositories/auth_repository.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/features/auth/application/sign_in_controller.dart';
import 'package:dilbaz_app/features/auth/application/sign_in_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository auth;
  late ProviderContainer container;

  setUp(() {
    auth = FakeAuthRepository();
    // Listening keeps the auto-disposed controller alive for the test.
    container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
    )..listen(signInControllerProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  SignInController controller() =>
      container.read(signInControllerProvider.notifier);
  SignInState state() => container.read(signInControllerProvider);

  test('starts by asking for the email', () {
    expect(state(), const SignInState.enterEmail());
  });

  test('a valid email sends a code and asks for it', () async {
    await controller().submitEmail('  Berat@Example.COM ');
    expect(auth.sentTo, ['berat@example.com']);
    expect(state(), const SignInState.enterCode(email: 'berat@example.com'));
  });

  test('a malformed email is caught before any request', () async {
    await controller().submitEmail('berat.example.com');
    expect(auth.sentTo, isEmpty);
    expect(
      state(),
      const SignInState.enterEmail(failure: AuthFailure.invalidEmail),
    );
  });

  test('an email outside the allowlist stays on the email step', () async {
    auth.sendFailure = AuthFailure.notAllowed;
    await controller().submitEmail('stranger@example.com');
    expect(
      state(),
      const SignInState.enterEmail(failure: AuthFailure.notAllowed),
    );
  });

  test('a correct code signs in', () async {
    await controller().submitEmail('berat@example.com');
    await controller().submitCode(' 123456 ');
    expect(auth.verified, [('berat@example.com', '123456')]);
    expect(auth.isSignedIn, isTrue);
    expect(
      state(),
      const SignInState.verifyingCode(email: 'berat@example.com'),
    );
  });

  test('a code that is not six digits is caught locally', () async {
    await controller().submitEmail('berat@example.com');
    await controller().submitCode('12a4');
    expect(auth.verified, isEmpty);
    expect(
      state(),
      const SignInState.enterCode(
        email: 'berat@example.com',
        failure: AuthFailure.invalidCode,
      ),
    );
  });

  test('a wrong code lets the learner try again', () async {
    auth.verifyFailure = AuthFailure.invalidCode;
    await controller().submitEmail('berat@example.com');
    await controller().submitCode('000000');
    expect(auth.isSignedIn, isFalse);
    expect(
      state(),
      const SignInState.enterCode(
        email: 'berat@example.com',
        failure: AuthFailure.invalidCode,
      ),
    );
  });

  test('resending keeps the code step and reports failures there', () async {
    await controller().submitEmail('berat@example.com');
    auth.sendFailure = AuthFailure.rateLimited;
    await controller().resendCode();
    expect(auth.sentTo, ['berat@example.com', 'berat@example.com']);
    expect(
      state(),
      const SignInState.enterCode(
        email: 'berat@example.com',
        failure: AuthFailure.rateLimited,
      ),
    );
  });

  test('the email can be changed from the code step', () async {
    await controller().submitEmail('berat@example.com');
    controller().changeEmail();
    expect(state(), const SignInState.enterEmail());
  });

  test('code actions outside the code step are ignored', () async {
    await controller().submitCode('123456');
    await controller().resendCode();
    expect(auth.verified, isEmpty);
    expect(auth.sentTo, isEmpty);
  });
}
