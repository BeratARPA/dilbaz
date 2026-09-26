import 'package:dilbaz_app/core/result.dart';

/// Why a sign-in step did not work; each maps to a calm UI text.
enum AuthFailure {
  invalidEmail,
  notAllowed,
  invalidCode,
  rateLimited,
  network,
  unknown,
}

/// Sign-in with a 6-digit email code (docs/14-security-privacy.md §2).
abstract interface class AuthRepository {
  bool get isSignedIn;

  /// Emits whenever the signed-in state changes.
  Stream<bool> watchSignedIn();

  /// Sends a code to [email]; unknown emails are rejected by the allowlist.
  Future<Result<void, AuthFailure>> sendCode(String email);

  /// Signs in with the [code] that was sent to [email].
  Future<Result<void, AuthFailure>> verifyCode({
    required String email,
    required String code,
  });

  Future<void> signOut();
}
