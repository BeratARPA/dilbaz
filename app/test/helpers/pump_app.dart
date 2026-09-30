import 'package:dilbaz_app/app/app.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/features/content/application/content_controller.dart';
import 'package:dilbaz_app/features/content/application/content_status.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';
import 'fake_profile_repository.dart';

/// Content as the app has it once the course packs are imported.
const ContentStatus readyContent = ContentStatus.ready(
  words: 600,
  chunks: 120,
  sentences: 588,
);

/// Turkish UI strings, so tests never hard-code user-visible text.
final AppLocalizations trStrings = lookupAppLocalizations(const Locale('tr'));

/// Fakes for everything the app reaches outside itself, with the course
/// content already on the device. Unless [profiles] says otherwise, the
/// learner has finished the welcome flow.
List<Override> appOverrides({
  required FakeAuthRepository auth,
  FakeProfileRepository? profiles,
  FakeTeamRepository? teams,
  FakePermissionGateway? permissions,
}) => [
  authRepositoryProvider.overrideWithValue(auth),
  profileRepositoryProvider.overrideWithValue(
    profiles ?? FakeProfileRepository(onboarded: true),
  ),
  teamRepositoryProvider.overrideWithValue(teams ?? FakeTeamRepository()),
  permissionGatewayProvider.overrideWithValue(
    permissions ?? FakePermissionGateway(),
  ),
  contentControllerProvider.overrideWithBuild((ref, notifier) => readyContent),
];

extension PumpApp on WidgetTester {
  /// Pumps the whole app with a fresh provider scope over [appOverrides].
  Future<FakeAuthRepository> pumpDilbazApp({
    bool signedIn = true,
    FakeAuthRepository? auth,
    FakeProfileRepository? profiles,
    FakeTeamRepository? teams,
    FakePermissionGateway? permissions,
  }) async {
    final fake = auth ?? FakeAuthRepository(signedIn: signedIn);
    await pumpWidget(
      ProviderScope(
        overrides: appOverrides(
          auth: fake,
          profiles: profiles,
          teams: teams,
          permissions: permissions,
        ),
        child: const DilbazApp(),
      ),
    );
    await pumpAndSettle();
    return fake;
  }
}
