import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/features/monthly/presentation/monthly_screen.dart';
import 'package:dilbaz_app/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/pump_app.dart';
import '../speaking/speaking_controller_test.dart' show marks, said;

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakeTutorRepository tutor;
  late FakeSpeechRepository speech;
  late FakeAnswerRecorder recorder;

  setUp(() {
    profiles = FakeProfileRepository(onboarded: true);
    tutor = FakeTutorRepository()..annotated = marks;
    speech = FakeSpeechRepository(heard: said);
    recorder = FakeAnswerRecorder()..duration = const Duration(seconds: 50);
  });

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    // The scroll takes effect in the next frame.
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  /// Today on the first day of the month, with the packs.
  Future<void> openToday(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      profiles: profiles,
      speech: speech,
      recorder: recorder,
      db: db,
      extra: cardDataOverrides(db: db, tutor: tutor),
    );
  }

  /// Starts speaking, then stops: the recording's clock never settles.
  Future<void> record(WidgetTester tester) async {
    await tapText(tester, trStrings.speakingStart);
    await tester.ensureVisible(find.text(trStrings.speakingStop));
    await tester.pump();
    await tester.tap(find.text(trStrings.speakingStop));
    await tester.pumpAndSettle();
  }

  /// From the invitation through the microphone check.
  Future<void> begin(WidgetTester tester) async {
    await tapText(tester, trStrings.monthlyInviteStart);
    await tapText(tester, trStrings.monthlyBegin);
    await tapText(tester, trStrings.monthlyMicTry);
    await tester.pump();
    await tapText(tester, trStrings.monthlyMicOk);
  }

  testWidgets('Today invites on the first days; "Şimdi değil" waits', (
    tester,
  ) async {
    await openToday(tester);
    expect(find.text(trStrings.monthlyInviteTitle), findsOneWidget);
    await tapText(tester, trStrings.monthlyInviteLater);
    expect(find.text(trStrings.monthlyInviteTitle), findsNothing);
  });

  testWidgets('the test: microphone, two tasks, then the report', (
    tester,
  ) async {
    await openToday(tester);
    await tapText(tester, trStrings.monthlyInviteStart);
    expect(find.byType(MonthlyScreen), findsOneWidget);
    expect(find.text(trStrings.monthlyIntro(2, 2)), findsOneWidget);
    await tapText(tester, trStrings.monthlyBegin);
    expect(find.text(trStrings.monthlyMicCheck), findsOneWidget);
    await tapText(tester, trStrings.monthlyMicTry);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tapText(tester, trStrings.monthlyMicOk);

    expect(find.text(trStrings.monthlyTaskNumber(1, 2)), findsOneWidget);
    expect(find.text(trStrings.monthlyAnchorNote), findsOneWidget);
    expect(find.text('Kendini tanıt: anlat.'), findsOneWidget);
    expect(find.text(trStrings.speakingPreparation(30)), findsOneWidget);
    // No phrases, no way out to another task in a test.
    expect(find.text(trStrings.speakingPhrases), findsNothing);
    expect(find.text(trStrings.speakingOtherTask), findsNothing);
    await record(tester);

    expect(find.text(trStrings.monthlyTaskNumber(2, 2)), findsOneWidget);
    expect(find.text('Şehrin: anlat.'), findsOneWidget);
    await record(tester);

    expect(find.text(trStrings.monthlyReportTitle), findsOneWidget);
    expect(find.text('Kendini tanıt'), findsOneWidget);
    expect(find.text(trStrings.monthlyErrorFree(2, 1)), findsNWidgets(2));
    expect(find.text(trStrings.speakingStats(0, 2, 5)), findsNWidgets(2));
    await tapText(tester, trStrings.monthlyWhatIsThis);
    expect(find.text(trStrings.monthlyExplainPauses), findsOneWidget);

    await tapText(tester, trStrings.cardsClose);
    expect(find.byType(TodayScreen), findsOneWidget);
    // This month's test is taken: no invitation any more.
    expect(find.text(trStrings.monthlyInviteTitle), findsNothing);
  });

  testWidgets('leaving needs no confirmation', (tester) async {
    await openToday(tester);
    await begin(tester);
    await tester.tap(find.byTooltip(trStrings.monthlyLeave));
    await tester.pumpAndSettle();
    expect(find.byType(MonthlyScreen), findsNothing);
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('every view fits a small phone at double text size', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final handle = tester.ensureSemantics();
    Future<void> check() async {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    }

    await openToday(tester);
    await check();
    await tapText(tester, trStrings.monthlyInviteStart);
    await check();
    await tapText(tester, trStrings.monthlyBegin);
    await check();
    await tapText(tester, trStrings.monthlyMicOk);
    await check();
    await record(tester);
    await record(tester);
    await check();
    handle.dispose();
  });
}
