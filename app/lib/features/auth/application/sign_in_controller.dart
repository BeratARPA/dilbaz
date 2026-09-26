import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/auth_repository.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/features/auth/application/sign_in_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sign_in_controller.g.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _codePattern = RegExp(r'^\d{6}$');

@riverpod
class SignInController extends _$SignInController {
  @override
  SignInState build() => const SignInState.enterEmail();

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  Future<void> submitEmail(String input) async {
    final email = input.trim().toLowerCase();
    if (!_emailPattern.hasMatch(email)) {
      state = const SignInState.enterEmail(failure: AuthFailure.invalidEmail);
      return;
    }
    await _sendCode(email, onFailure: SignInState.enterEmail);
  }

  Future<void> resendCode() async {
    if (state case SignInEnterCode(:final email)) {
      await _sendCode(
        email,
        onFailure: ({failure}) =>
            SignInState.enterCode(email: email, failure: failure),
      );
    }
  }

  void changeEmail() => state = const SignInState.enterEmail();

  Future<void> submitCode(String input) async {
    final current = state;
    if (current is! SignInEnterCode) return;
    final code = input.trim();
    if (!_codePattern.hasMatch(code)) {
      state = current.copyWith(failure: AuthFailure.invalidCode);
      return;
    }
    state = SignInState.verifyingCode(email: current.email);
    final result = await _auth.verifyCode(email: current.email, code: code);
    if (!ref.mounted) return;
    if (result case Err(:final error)) {
      state = SignInState.enterCode(email: current.email, failure: error);
    }
  }

  Future<void> _sendCode(
    String email, {
    required SignInState Function({AuthFailure? failure}) onFailure,
  }) async {
    state = SignInState.sendingCode(email: email);
    final result = await _auth.sendCode(email);
    if (!ref.mounted) return;
    state = switch (result) {
      Ok() => SignInState.enterCode(email: email),
      Err(:final error) => onFailure(failure: error),
    };
  }
}
