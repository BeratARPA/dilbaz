import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:dilbaz_app/features/together/presentation/info_gap_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_together.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/pump_app.dart';
import '../speaking/speaking_controller_test.dart' show marks;
import 'info_gap_test.dart' show theirs;
import 'together_test.dart' show partnerId, team;

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
      extra: cardDataOverrides(
        db: db,
        tutor: FakeTutorRepository()..annotated = marks,
      ),
    );
    if (tab) await tapText(tester, trStrings.tabTogether);
  }

  testWidgets('a task is started from the tab and waits for the partner', (
    tester,
  ) async {
    await open(tester);
    expect(find.text(trStrings.gapTasksTitle), findsOneWidget);
    await tapText(tester, 'Arkadaşımı bul');
    expect(find.byType(InfoGapScreen), findsOneWidget);
    expect(find.text(trStrings.gapWaiting), findsOneWidget);
    await tapText(tester, trStrings.togetherCancel);
    expect(find.byType(InfoGapScreen), findsNothing);
    expect(
      server.calls,
      contains('cancel-session ${server.allSessions.single.id}'),
    );
  });

  testWidgets("from Today: join the partner's task, choose, see how it went", (
    tester,
  ) async {
    server.putSession(theirs(gapChoose));
    await open(tester, tab: false);
    expect(
      find.text(trStrings.gapOpenPartner('Ada', 'Arkadaşımı bul')),
      findsOneWidget,
    );
    await tapText(tester, trStrings.gapOpen);
    await tapText(tester, trStrings.gapJoin);
    expect(find.text('Sen bul.'), findsOneWidget, reason: 'role b');
    expect(find.text('Bada kolu.'), findsNothing, reason: "role a's lines");
    await tapText(tester, 'Bada kolu, sima dero.');
    await tapText(tester, trStrings.gapSubmit);
    expect(find.text(trStrings.gapAnswered), findsOneWidget);

    server.partnerAnswers('their-session', partnerId, 'done');
    await tester.pumpAndSettle();
    expect(find.text(trStrings.gapSolved), findsOneWidget);
    expect(find.text(trStrings.gapNothingSaid), findsOneWidget);
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

    server.putSession(theirs(gapDifferences, state: PairState.active));
    await open(tester);
    await check();
    await tapText(tester, trStrings.gapOpen);
    await check();
    handle.dispose();
  });
}
