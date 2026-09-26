import 'package:dilbaz_app/app/app.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

/// Turkish UI strings, so tests never hard-code user-visible text.
final AppLocalizations trStrings = lookupAppLocalizations(const Locale('tr'));

extension PumpApp on WidgetTester {
  /// Pumps the whole app with a fresh provider scope and fake auth.
  Future<FakeAuthRepository> pumpDilbazApp({
    bool signedIn = true,
    FakeAuthRepository? auth,
  }) async {
    final fake = auth ?? FakeAuthRepository(signedIn: signedIn);
    await pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
        child: const DilbazApp(),
      ),
    );
    await pumpAndSettle();
    return fake;
  }
}
