import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/features/progress/presentation/progress_screen.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../../helpers/pump_app.dart';
import 'progress_controller_test.dart' show heard, marked;

void main() {
  late AppDatabase db;
  late FakeClipPlayer player;

  setUp(() => player = FakeClipPlayer());

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    // The scroll takes effect in the next frame.
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  /// The Progress tab, with two monthly recordings of the anchor.
  Future<void> openProgress(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
      for (final (id, daysAgo) in [('sep', 30), ('oct', 0)]) {
        final recordings = DriftRecordingRepository(
          db,
          now: () => cardNow.subtract(Duration(days: daysAgo)),
        );
        await recordings.create(
          id: id,
          userId: FakeAuthRepository.id,
          courseId: FakeAssessmentRepository.zzCourse.id,
          taskRef: anchorTask,
          audioPath: '/recordings/$id.m4a',
          duration: const Duration(seconds: 40),
          isAssessment: true,
        );
        await recordings.update(
          id,
          transcript: heard,
          annotated: marked(TaskOutcome.done),
        );
      }
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      player: player,
      db: db,
      extra: cardDataOverrides(db: db, tutor: FakeTutorRepository()),
    );
    await tapText(tester, trStrings.tabProgress);
  }

  testWidgets('Progress shows counts, can-dos and the recordings', (
    tester,
  ) async {
    await openProgress(tester);
    expect(find.byType(ProgressScreen), findsOneWidget);
    expect(find.text(trStrings.progressEvidenceTitle), findsOneWidget);
    expect(find.text(trStrings.progressUsed), findsOneWidget);
    await tapText(tester, trStrings.progressWhatAreThese);
    expect(find.text(trStrings.progressExplainUsed), findsOneWidget);

    expect(find.text('Kendini anlatabilirsin.'), findsOneWidget);
    expect(find.text(trStrings.progressCanDoShown), findsOneWidget);
    expect(find.text(trStrings.progressCanDoNone), findsOneWidget);

    expect(find.text('Kendini tanıt'), findsOneWidget);
    await tester.ensureVisible(find.byIcon(Icons.play_arrow).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pumpAndSettle();
    expect(player.played, ['/recordings/sep.m4a']);
    expect(
      find.textContaining(trStrings.progressClauses(2, 1)),
      findsNWidgets(2),
    );
  });

  testWidgets('every part fits a small phone at double text size', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final handle = tester.ensureSemantics();
    await openProgress(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.ensureVisible(find.byIcon(Icons.play_arrow).last);
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
