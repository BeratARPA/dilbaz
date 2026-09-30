import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';
import 'package:dilbaz_app/features/onboarding/application/onboarding_state.dart';
import 'package:dilbaz_app/features/onboarding/presentation/onboarding_screen.dart';
import 'package:dilbaz_app/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_profile_repository.dart';
import '../../helpers/pump_app.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    // The scroll takes effect in the next frame.
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String label, String text) async {
    await tester.enterText(field(label), text);
    await tester.pump();
  }

  /// The button that leaves each step forwards when nothing is answered.
  String forward(OnboardingStep step) => switch (step) {
    OnboardingStep.welcome => trStrings.onboardingStart,
    OnboardingStep.notifications => trStrings.onboardingNotifyLater,
    OnboardingStep.partner => trStrings.onboardingSkip,
    OnboardingStep.level => trStrings.onboardingFinish,
    _ => trStrings.onboardingNext,
  };

  /// Walks the flow to [step], giving only the name.
  Future<void> walkTo(WidgetTester tester, OnboardingStep step) async {
    for (final current in OnboardingStep.values.take(step.index)) {
      if (current == OnboardingStep.name) {
        await type(tester, trStrings.onboardingNameLabel, 'Berat');
      }
      await tapText(tester, forward(current));
    }
  }

  bool enabled(WidgetTester tester, String label) =>
      tester
          .widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.bySubtype<ButtonStyleButton>(),
            ),
          )
          .onPressed !=
      null;

  testWidgets('a new learner is welcomed with the three principles', (
    tester,
  ) async {
    await tester.pumpDilbazApp(profiles: FakeProfileRepository());

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text(trStrings.onboardingWelcomeTitle), findsOneWidget);
    for (final principle in [
      trStrings.onboardingPrinciple1,
      trStrings.onboardingPrinciple2,
      trStrings.onboardingPrinciple3,
    ]) {
      expect(find.text(principle), findsOneWidget);
    }
    // The first step has no way back.
    expect(find.text(trStrings.onboardingBack), findsNothing);
  });

  testWidgets('the whole flow saves the answers and opens Today', (
    tester,
  ) async {
    final profiles = FakeProfileRepository();
    final permissions = FakePermissionGateway();
    await tester.pumpDilbazApp(profiles: profiles, permissions: permissions);

    await tapText(tester, trStrings.onboardingStart);

    // The name is the one thing the flow insists on.
    expect(enabled(tester, trStrings.onboardingNext), isFalse);
    expect(find.text(trStrings.onboardingCourseNote), findsOneWidget);
    await type(tester, trStrings.onboardingNameLabel, 'Berat');
    await tapText(tester, trStrings.onboardingNext);

    expect(find.text(trStrings.onboardingGoalTitle), findsOneWidget);
    await tapText(tester, trStrings.goalTravel);
    await tapText(tester, trStrings.goalWork);
    await tapText(tester, trStrings.goalConversation);
    await tapText(tester, trStrings.goalWork);
    await type(tester, trStrings.onboardingGoalTextLabel, 'Rahat konuşmak');
    await tapText(tester, trStrings.onboardingNext);

    expect(find.text(trStrings.onboardingTimeNote), findsOneWidget);
    await tapText(tester, trStrings.onboardingBudgetMinutes(15));
    await tapText(tester, '4');
    await tapText(tester, trStrings.onboardingNext);

    await tapText(tester, trStrings.anchorAfterDinner);
    expect(find.text(trStrings.onboardingAnchorTime('20:00')), findsOneWidget);
    await tapText(tester, trStrings.onboardingNext);

    expect(find.text(trStrings.onboardingNotifyBody), findsOneWidget);
    expect(permissions.asked, isEmpty);
    await tapText(tester, trStrings.onboardingNotifyAllow);
    expect(permissions.asked, ['notifications']);

    expect(find.text(trStrings.onboardingPartnerBody), findsOneWidget);
    await tapText(tester, trStrings.onboardingSkip);

    // Both consents start off; the learner gives them, nothing else does.
    expect(find.text(trStrings.onboardingAudioOffNote), findsOneWidget);
    await tapText(tester, trStrings.onboardingAudioConsent);
    expect(permissions.asked, ['notifications', 'microphone']);
    expect(find.text(trStrings.onboardingAudioOffNote), findsNothing);
    await tapText(tester, trStrings.onboardingAiConsent);
    await tapText(tester, trStrings.onboardingNext);

    expect(find.text(trStrings.onboardingLevelBody), findsOneWidget);
    await tapText(tester, trStrings.levelA2);
    await tapText(tester, trStrings.onboardingFinish);

    expect(profiles.saved, [
      (
        const OnboardingAnswers(
          displayName: 'Berat',
          goals: {'travel', 'conversation'},
          goalText: 'Rahat konuşmak',
          timeBudgetMin: 15,
          weeklyDaysGoal: 4,
          anchor: 'after_dinner',
          anchorTime: '20:00',
          notifications: true,
          audioConsent: true,
          microphone: true,
          aiDataConsent: true,
          level: 'A2',
        ),
        true,
      ),
    ]);
    expect(profiles.pushes, 1);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('nothing but the name needs an answer', (tester) async {
    final profiles = FakeProfileRepository();
    final permissions = FakePermissionGateway();
    await tester.pumpDilbazApp(profiles: profiles, permissions: permissions);

    await walkTo(tester, OnboardingStep.level);
    await tapText(tester, trStrings.onboardingFinish);

    // No consent is given and no permission asked for unless the learner
    // chooses so.
    expect(permissions.asked, isEmpty);
    expect(profiles.saved.single, (
      const OnboardingAnswers(displayName: 'Berat'),
      true,
    ));
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('going back keeps what was answered', (tester) async {
    await tester.pumpDilbazApp(profiles: FakeProfileRepository());
    await walkTo(tester, OnboardingStep.goal);
    await tapText(tester, trStrings.goalMedia);
    await type(tester, trStrings.onboardingGoalTextLabel, 'Dizi izlemek');
    await tapText(tester, trStrings.onboardingBack);

    expect(find.widgetWithText(TextField, 'Berat'), findsOneWidget);
    await tapText(tester, trStrings.onboardingNext);

    expect(find.widgetWithText(TextField, 'Dizi izlemek'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(
            find.widgetWithText(FilterChip, trStrings.goalMedia),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('the system back button walks the steps too', (tester) async {
    await tester.pumpDilbazApp(profiles: FakeProfileRepository());
    await walkTo(tester, OnboardingStep.time);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(trStrings.onboardingGoalTitle), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Berat'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(trStrings.onboardingWelcomeTitle), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('a step opens at its top, however far the last was scrolled', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 480)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpDilbazApp(profiles: FakeProfileRepository());
    await walkTo(tester, OnboardingStep.voice);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text(trStrings.onboardingVoiceTitle)).dy,
      lessThan(0),
    );
    await tapText(tester, trStrings.onboardingNext);

    expect(
      tester.getTopLeft(find.text(trStrings.onboardingLevelTitle)).dy,
      greaterThan(0),
    );
  });

  testWidgets('the anchor time can be set by hand', (tester) async {
    final profiles = FakeProfileRepository();
    await tester.pumpDilbazApp(profiles: profiles);
    await walkTo(tester, OnboardingStep.anchor);

    await tapText(tester, trStrings.anchorBeforeBed);
    await tapText(tester, trStrings.onboardingAnchorTime('22:30'));
    final material = MaterialLocalizations.of(
      tester.element(find.byType(TimePickerDialog)),
    );
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '7');
    await tester.enterText(find.byType(TextField).at(1), '5');
    await tapText(tester, material.okButtonLabel);

    expect(find.text(trStrings.onboardingAnchorTime('07:05')), findsOneWidget);

    // Leaving the dialog changes nothing.
    await tapText(tester, trStrings.onboardingAnchorTime('07:05'));
    await tapText(tester, material.cancelButtonLabel);
    expect(find.text(trStrings.onboardingAnchorTime('07:05')), findsOneWidget);
  });

  group('team step', () {
    testWidgets('creating a team shows the code to pass on', (tester) async {
      final profiles = FakeProfileRepository();
      final teams = FakeTeamRepository();
      await tester.pumpDilbazApp(profiles: profiles, teams: teams);
      await walkTo(tester, OnboardingStep.partner);

      // A team needs a name before it can be asked for.
      expect(enabled(tester, trStrings.onboardingTeamCreate), isFalse);
      expect(enabled(tester, trStrings.onboardingTeamJoin), isFalse);
      await type(tester, trStrings.onboardingTeamNameLabel, 'Biz');
      await tapText(tester, trStrings.onboardingTeamCreate);

      expect(teams.created, ['Biz']);
      // The profile went to the server first, not yet finished.
      expect(profiles.saved.single.$2, isFalse);
      expect(
        find.text(trStrings.onboardingTeamCreated(FakeTeamRepository.code)),
        findsOneWidget,
      );
      expect(find.text(trStrings.onboardingSkip), findsNothing);
      await tapText(tester, trStrings.onboardingNext);
      expect(find.text(trStrings.onboardingVoiceTitle), findsOneWidget);
    });

    testWidgets('a wrong code gets a calm note, the right one joins', (
      tester,
    ) async {
      final teams = FakeTeamRepository();
      await tester.pumpDilbazApp(
        profiles: FakeProfileRepository(),
        teams: teams,
      );
      await walkTo(tester, OnboardingStep.partner);

      await type(tester, trStrings.onboardingInviteCodeLabel, 'FFFFFFFFFF');
      await tapText(tester, trStrings.onboardingTeamJoin);
      expect(find.text(trStrings.teamFailureInviteNotFound), findsOneWidget);
      // An icon beside the text: colour is never the only signal.
      expect(find.byIcon(Icons.info_outline), findsOneWidget);

      await type(
        tester,
        trStrings.onboardingInviteCodeLabel,
        FakeTeamRepository.code,
      );
      await tapText(tester, trStrings.onboardingTeamJoin);
      expect(teams.joined, [FakeTeamRepository.code]);
      expect(find.text(trStrings.onboardingTeamJoined('Biz')), findsOneWidget);
      expect(find.text(trStrings.teamFailureInviteNotFound), findsNothing);
    });
  });

  testWidgets('every step fits a small phone at double text size', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final handle = tester.ensureSemantics();

    await tester.pumpDilbazApp(profiles: FakeProfileRepository());
    for (final step in OnboardingStep.values) {
      // A layout that does not fit throws while it is pumped.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      if (step == OnboardingStep.name) {
        await type(tester, trStrings.onboardingNameLabel, 'Berat');
      }
      await tapText(tester, forward(step));
    }
    expect(find.byType(TodayScreen), findsOneWidget);
    handle.dispose();
  });
}
