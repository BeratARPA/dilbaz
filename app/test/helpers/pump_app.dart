import 'package:dilbaz_app/app/app.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/features/content/application/content_controller.dart';
import 'package:dilbaz_app/features/content/application/content_status.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

/// Content as the app has it once the course packs are imported.
const ContentStatus readyContent = ContentStatus.ready(
  words: 600,
  chunks: 120,
  sentences: 588,
);

/// Turkish UI strings, so tests never hard-code user-visible text.
final AppLocalizations trStrings = lookupAppLocalizations(const Locale('tr'));

extension PumpApp on WidgetTester {
  /// Pumps the whole app with a fresh provider scope, fake auth and the
  /// course content already on the device.
  Future<FakeAuthRepository> pumpDilbazApp({
    bool signedIn = true,
    FakeAuthRepository? auth,
  }) async {
    final fake = auth ?? FakeAuthRepository(signedIn: signedIn);
    await pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fake),
          contentControllerProvider.overrideWithBuild(
            (ref, notifier) => readyContent,
          ),
        ],
        child: const DilbazApp(),
      ),
    );
    await pumpAndSettle();
    return fake;
  }
}
