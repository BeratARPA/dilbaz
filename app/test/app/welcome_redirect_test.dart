import 'package:dilbaz_app/app/app.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/features/auth/presentation/sign_in_screen.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:dilbaz_app/features/onboarding/presentation/onboarding_screen.dart';
import 'package:dilbaz_app/features/onboarding/presentation/opening_screen.dart';
import 'package:dilbaz_app/features/today/presentation/today_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_profile_repository.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('a learner without a profile is welcomed first', (tester) async {
    final profiles = FakeProfileRepository();
    await tester.pumpDilbazApp(profiles: profiles);

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing);
    // The server was asked for a profile made elsewhere.
    expect(profiles.restores, 1);
  });

  testWidgets('a profile made on another device opens Today at once', (
    tester,
  ) async {
    final profiles = FakeProfileRepository(onServer: true);
    await tester.pumpDilbazApp(profiles: profiles);

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('a known learner never sees the opening page', (tester) async {
    final container = ProviderContainer(
      overrides: appOverrides(auth: FakeAuthRepository(signedIn: true)),
    );
    addTearDown(container.dispose);

    // As in `main`: the launch screen stays until the start is known.
    // Outside a widget tree providers rebuild on a timer, which the test
    // clock has to run.
    final settled = startSettled(container);
    await tester.pump(const Duration(milliseconds: 1));
    await settled;
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DilbazApp()),
    );

    // The very first frame.
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(OpeningScreen), findsNothing);
  });

  testWidgets('signing in without a profile leads to the welcome flow', (
    tester,
  ) async {
    final auth = await tester.pumpDilbazApp(
      signedIn: false,
      profiles: FakeProfileRepository(),
    );
    expect(find.byType(SignInScreen), findsOneWidget);

    await auth.verifyCode(email: 'b@dilbaz.test', code: '123456');
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing);
  });

  testWidgets('signing out of the welcome flow returns to the sign-in page', (
    tester,
  ) async {
    final auth = await tester.pumpDilbazApp(profiles: FakeProfileRepository());
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await auth.signOut();
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('while the server cannot be asked, the app offers to ask again', (
    tester,
  ) async {
    final profiles = FakeProfileRepository(onServer: true)
      ..failure = ProfileFailure.network;
    await tester.pumpDilbazApp(profiles: profiles);

    // A profile may exist elsewhere, so the welcome flow does not start.
    expect(find.byType(OpeningScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text(trStrings.openingUnreachable), findsOneWidget);

    profiles.failure = null;
    await tester.tap(find.text(trStrings.openingRetry));
    await tester.pumpAndSettle();

    expect(profiles.restores, 2);
    expect(find.byType(TodayScreen), findsOneWidget);
  });
}
