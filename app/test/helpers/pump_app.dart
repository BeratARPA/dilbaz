import 'package:dilbaz_app/app/app.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Turkish UI strings, so tests never hard-code user-visible text.
final AppLocalizations trStrings = lookupAppLocalizations(const Locale('tr'));

extension PumpApp on WidgetTester {
  /// Pumps the whole app with a fresh provider scope.
  Future<void> pumpDilbazApp() async {
    await pumpWidget(const ProviderScope(child: DilbazApp()));
    await pumpAndSettle();
  }
}
