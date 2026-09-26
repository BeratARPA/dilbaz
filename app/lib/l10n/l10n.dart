import 'package:dilbaz_app/l10n/gen/app_localizations.dart';
import 'package:flutter/widgets.dart';

export 'package:dilbaz_app/l10n/gen/app_localizations.dart';

/// Short access to the UI strings; every user-visible text comes from ARB.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
