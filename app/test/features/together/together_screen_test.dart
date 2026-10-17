import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:dilbaz_app/features/gap_journal/presentation/gap_capture_screen.dart';
import 'package:dilbaz_app/features/together/presentation/chat_card_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_together.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/pump_app.dart';
import 'together_test.dart' show invited, partnerId, self, team;

void main() {
  late AppDatabase db;
  late FakeTogetherRepository server;

  setUp(() => server = FakeTogetherRepository(teamView: team));

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool tab = true}) async {
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      db: db,
      together: server,
      extra: cardDataOverrides(db: db, tutor: FakeTutorRepository()),
    );
    if (tab) await tapText(tester, trStrings.tabTogether);
  }

  testWidgets('the partner, the cards; a card is talked through', (
    tester,
  ) async {
    server.setHere({partnerId});
    await open(tester);
    expect(find.text(trStrings.togetherPartnerHere('Ada')), findsOneWidget);
    expect(find.text(trStrings.togetherCardsTitle), findsWidgets);
    await tapText(tester, 'Yemek');
    expect(find.byType(ChatCardScreen), findsOneWidget);
    expect(find.text('Bada $chatA?'), findsOneWidget);
    expect(find.text('Yemek sorusu'), findsOneWidget, reason: 'its meaning');

    await tapText(tester, trStrings.chatInvite);
    expect(server.calls, contains('invite $partnerId $chatA'));
    expect(find.text(trStrings.chatInvite), findsNothing, reason: 'sent');

    await tapText(tester, trStrings.chatStart);
    expect(find.text(trStrings.chatTalking), findsOneWidget);
    await tapText(tester, trStrings.chatFinish);
    expect(find.text(trStrings.chatDone(1)), findsOneWidget);
    await tapText(tester, trStrings.gapCaptureButton);
    expect(find.byType(GapCaptureScreen), findsOneWidget);
  });

  testWidgets("the partner's invitation: yes opens the card", (tester) async {
    server.receive(invited());
    await open(tester);
    expect(
      find.text(trStrings.togetherIncoming('Ada', 'Yemek')),
      findsOneWidget,
    );
    await tapText(tester, trStrings.togetherYes);
    expect(find.byType(ChatCardScreen), findsOneWidget);
    expect(server.calls, contains('answer from-partner true'));
  });

  testWidgets('Today shows the invitation, and then the agreed card', (
    tester,
  ) async {
    server.receive(invited());
    await open(tester, tab: false);
    expect(
      find.text(trStrings.togetherIncoming('Ada', 'Yemek')),
      findsOneWidget,
    );
    await tapText(tester, trStrings.togetherNotNow);
    expect(find.text(trStrings.togetherIncoming('Ada', 'Yemek')), findsNothing);
    expect(server.calls, contains('answer from-partner false'));
  });

  testWidgets('without the server: it says so and can try again', (
    tester,
  ) async {
    server.failure = TogetherFailure.network;
    await open(tester);
    expect(find.text(trStrings.togetherOffline), findsOneWidget);
    server.failure = null;
    await tapText(tester, trStrings.togetherRetry);
    expect(find.text(trStrings.togetherPartnerAway('Ada')), findsOneWidget);
  });

  testWidgets('the shared goal; a cheer is sent and one arrives', (
    tester,
  ) async {
    server
      ..teamWeek = (
        goalDays: 9,
        members: [
          (
            id: self,
            name: 'Berat',
            days: 2,
            minutes: 40,
            strands: const {},
            together: 1,
          ),
          (
            id: partnerId,
            name: 'Ada',
            days: 3,
            minutes: 55,
            strands: const {},
            together: 1,
          ),
        ],
      )
      ..cheered((
        id: 'c1',
        from: partnerId,
        to: self,
        key: CheerKey.speaking,
        createdAt: cardNow,
      ));
    await open(tester, tab: false);
    final received = trStrings.cheerReceived('Ada', trStrings.cheerSpeaking);
    expect(find.text(received), findsOneWidget, reason: 'on Today');
    await tapText(tester, trStrings.tabTogether);
    expect(find.text(trStrings.togetherGoal(5, 9)), findsOneWidget);
    expect(
      find.text(trStrings.togetherPartnerWeek('Ada', 3, 55, 1)),
      findsOneWidget,
    );
    await tapText(tester, trStrings.cheerSend);
    await tapText(tester, trStrings.cheerSteady);
    expect(find.text(trStrings.cheerSent), findsOneWidget);
    expect(server.calls, contains('cheer $partnerId steady'));
  });

  testWidgets('fits a small phone at double text size', (tester) async {
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

    server.receive(invited());
    await open(tester);
    await check();
    await tapText(tester, 'Tatil');
    await check();
    handle.dispose();
  });
}
