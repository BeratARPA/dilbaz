import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthRepository implements AuthRepository {
  const new(this._auth);

  final GoTrueClient _auth;

  @override
  bool get isSignedIn => _auth.currentSession != null;

  @override
  Stream<bool> watchSignedIn() =>
      _auth.onAuthStateChange.map((state) => state.session != null);

  @override
  Future<Result<void, AuthFailure>> sendCode(String email) async {
    try {
      await _auth.signInWithOtp(email: email);
      return const Ok(null);
    } on AuthException catch (error) {
      return Err(sendCodeFailure(error));
    }
  }

  @override
  Future<Result<void, AuthFailure>> verifyCode({
    required String email,
    required String code,
  }) async {
    try {
      await _auth.verifyOTP(email: email, token: code, type: OtpType.email);
      return const Ok(null);
    } on AuthException catch (error) {
      return Err(verifyCodeFailure(error));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

/// Maps a failed code request. The sign-up allowlist hook answers
/// 403 `signup_not_allowed` (supabase/migrations, docs/14 §2).
AuthFailure sendCodeFailure(AuthException error) => switch (error) {
  AuthRetryableFetchException(statusCode: null) => AuthFailure.network,
  AuthException(message: 'signup_not_allowed') => AuthFailure.notAllowed,
  AuthException(statusCode: '429') => AuthFailure.rateLimited,
  AuthException(statusCode: '400') => AuthFailure.invalidEmail,
  _ => AuthFailure.unknown,
};

/// Maps a failed code check; a wrong or expired code is 403 `otp_expired`.
AuthFailure verifyCodeFailure(AuthException error) => switch (error) {
  AuthRetryableFetchException(statusCode: null) => AuthFailure.network,
  AuthException(statusCode: '429') => AuthFailure.rateLimited,
  AuthException(statusCode: '400' || '403') => AuthFailure.invalidCode,
  _ => AuthFailure.unknown,
};
