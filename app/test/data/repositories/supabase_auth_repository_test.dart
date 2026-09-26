import 'package:dilbaz_app/data/repositories/auth_repository.dart';
import 'package:dilbaz_app/data/repositories/supabase_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error shapes observed from the local Auth server (F0-06 curl checks).
void main() {
  group('sendCodeFailure', () {
    test('the allowlist hook rejection means not allowed', () {
      const error = AuthApiException(
        'signup_not_allowed',
        statusCode: '403',
        code: 'unknown',
      );
      expect(sendCodeFailure(error), AuthFailure.notAllowed);
    });

    test('an invalid email address', () {
      const error = AuthApiException(
        'Unable to validate email address: invalid format',
        statusCode: '400',
        code: 'validation_failed',
      );
      expect(sendCodeFailure(error), AuthFailure.invalidEmail);
    });

    test('too many requests', () {
      const error = AuthApiException(
        'For security purposes, you can only request this after 0 seconds.',
        statusCode: '429',
        code: 'over_email_send_rate_limit',
      );
      expect(sendCodeFailure(error), AuthFailure.rateLimited);
    });

    test('no connection', () {
      expect(
        sendCodeFailure(AuthRetryableFetchException()),
        AuthFailure.network,
      );
    });

    test('server errors are unknown failures', () {
      expect(
        sendCodeFailure(AuthRetryableFetchException(statusCode: '503')),
        AuthFailure.unknown,
      );
    });
  });

  group('verifyCodeFailure', () {
    test('a wrong or expired code', () {
      const error = AuthApiException(
        'Token has expired or is invalid',
        statusCode: '403',
        code: 'otp_expired',
      );
      expect(verifyCodeFailure(error), AuthFailure.invalidCode);
    });

    test('too many attempts', () {
      const error = AuthApiException('slow down', statusCode: '429');
      expect(verifyCodeFailure(error), AuthFailure.rateLimited);
    });

    test('no connection', () {
      expect(
        verifyCodeFailure(AuthRetryableFetchException()),
        AuthFailure.network,
      );
    });

    test('anything else is unknown', () {
      const error = AuthApiException('boom', statusCode: '418');
      expect(verifyCodeFailure(error), AuthFailure.unknown);
    });
  });
}
