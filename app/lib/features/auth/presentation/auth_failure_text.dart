import 'package:dilbaz_app/data/repositories/auth_repository.dart';
import 'package:dilbaz_app/l10n/l10n.dart';

extension AuthFailureText on AuthFailure {
  String text(AppLocalizations l10n) => switch (this) {
    AuthFailure.invalidEmail => l10n.authFailureInvalidEmail,
    AuthFailure.notAllowed => l10n.authFailureNotAllowed,
    AuthFailure.invalidCode => l10n.authFailureInvalidCode,
    AuthFailure.rateLimited => l10n.authFailureRateLimited,
    AuthFailure.network => l10n.authFailureNetwork,
    AuthFailure.unknown => l10n.authFailureUnknown,
  };
}
