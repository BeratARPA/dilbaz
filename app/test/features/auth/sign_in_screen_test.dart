import 'package:dilbaz_app/data/repositories/auth_repository.dart';
import 'package:dilbaz_app/features/auth/presentation/sign_in_screen.dart';
import 'package:dilbaz_app/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/pump_app.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('signs in with an email code and lands on Today', (tester) async {
    final auth = await tester.pumpDilbazApp(signedIn: false);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.enterText(field(trStrings.signInEmailLabel), 'b@dilbaz.test');
    await tester.tap(find.text(trStrings.signInSendCode));
    await tester.pumpAndSettle();
    expect(find.text(trStrings.signInCodeSentTo('b@dilbaz.test')), findsOne);

    await tester.enterText(field(trStrings.signInCodeLabel), '123456');
    await tester.tap(find.text(trStrings.signInConfirm));
    await tester.pumpAndSettle();

    expect(auth.verified, [('b@dilbaz.test', '123456')]);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('shows a calm note with an icon when the code is wrong', (
    tester,
  ) async {
    final auth = FakeAuthRepository()..verifyFailure = AuthFailure.invalidCode;
    await tester.pumpDilbazApp(auth: auth);

    await tester.enterText(field(trStrings.signInEmailLabel), 'b@dilbaz.test');
    await tester.tap(find.text(trStrings.signInSendCode));
    await tester.pumpAndSettle();
    await tester.enterText(field(trStrings.signInCodeLabel), '000000');
    await tester.tap(find.text(trStrings.signInConfirm));
    await tester.pumpAndSettle();

    expect(find.text(trStrings.authFailureInvalidCode), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('the code field accepts digits only, six at most', (
    tester,
  ) async {
    await tester.pumpDilbazApp(signedIn: false);
    await tester.enterText(field(trStrings.signInEmailLabel), 'b@dilbaz.test');
    await tester.tap(find.text(trStrings.signInSendCode));
    await tester.pumpAndSettle();

    await tester.enterText(field(trStrings.signInCodeLabel), '12ab345678');
    final code = tester.widget<TextField>(field(trStrings.signInCodeLabel));
    expect(code.controller!.text, '123456');
  });

  testWidgets('the email can be changed after a code was sent', (tester) async {
    await tester.pumpDilbazApp(signedIn: false);
    await tester.enterText(field(trStrings.signInEmailLabel), 'b@dilbaz.test');
    await tester.tap(find.text(trStrings.signInSendCode));
    await tester.pumpAndSettle();

    await tester.tap(find.text(trStrings.signInChangeEmail));
    await tester.pumpAndSettle();
    expect(field(trStrings.signInEmailLabel), findsOneWidget);
    expect(field(trStrings.signInCodeLabel), findsNothing);
  });
}
