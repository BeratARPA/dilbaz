import 'package:dilbaz_app/features/auth/presentation/sign_in_screen.dart';
import 'package:dilbaz_app/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('a signed-out user sees only the sign-in page', (tester) async {
    await tester.pumpDilbazApp(signedIn: false);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing);
  });

  testWidgets('a signed-in user starts on Today', (tester) async {
    await tester.pumpDilbazApp();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });

  testWidgets('signing out from settings returns to the sign-in page', (
    tester,
  ) async {
    final auth = await tester.pumpDilbazApp();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(trStrings.tabProgress),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(trStrings.settingsTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(trStrings.signOut));
    await tester.pumpAndSettle();

    expect(auth.isSignedIn, isFalse);
    expect(find.byType(SignInScreen), findsOneWidget);
  });
}
