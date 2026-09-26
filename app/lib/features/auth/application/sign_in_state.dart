import 'package:dilbaz_app/data/repositories/auth_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'sign_in_state.freezed.dart';

/// Steps of the email-code sign-in.
@freezed
sealed class SignInState with _$SignInState {
  const factory enterEmail({AuthFailure? failure}) = SignInEnterEmail;

  const factory sendingCode({required String email}) = SignInSendingCode;

  const factory enterCode({required String email, AuthFailure? failure}) =
      SignInEnterCode;

  /// Also the final state: the router leaves the page once signed in.
  const factory verifyingCode({required String email}) = SignInVerifyingCode;
}
