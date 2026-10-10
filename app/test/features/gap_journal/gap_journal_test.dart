import 'dart:async';

import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/data/gap/gap_repository.dart';
import 'package:dilbaz_app/data/share/shared_text_source.dart';
import 'package:dilbaz_app/data/speech/dictation.dart';
import 'package:dilbaz_app/features/gap_journal/presentation/gap_capture_screen.dart';
import 'package:dilbaz_app/features/gap_journal/presentation/gap_entry_screen.dart';
import 'package:dilbaz_app/features/gap_journal/presentation/gap_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../../helpers/pump_app.dart';

/// Text shared from another app.
class FakeSharedTextSource implements SharedTextSource {
  new({this.first});

  String? first;
  final shared = StreamController<String>.broadcast();

  @override
  Future<String?> initial() async => first;

  @override
  Stream<String> texts() => shared.stream;

  @override
  Future<void> clear() async => first = null;
}

void main() {
  late AppDatabase db;
  late FakeTutorRepository tutor;
  late FakeDictation dictation;
  late FakeProfileRepository profiles;

  setUp(() {
    tutor = FakeTutorRepository();
    dictation = FakeDictation();
    profiles = FakeProfileRepository(onboarded: true);
  });

  Future<void> tapText(WidgetTester tester, String text) async {
    // A focused field scrolls itself back into view; let it go first.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  /// Starts dictation; the page shows an endless progress bar meanwhile,
  /// so it never settles.
  Future<void> listen(WidgetTester tester) async {
    await tester.tap(find.text(trStrings.gapCaptureDictate));
    await tester.pump();
    await tester.pump();
  }

  /// Stops dictation before its limit (30 s) runs out on the fake clock.
  Future<void> stop(WidgetTester tester) async {
    await tester.tap(find.text(trStrings.gapCaptureStop));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {SharedTextSource? shared}) async {
    await tester.runAsync(() async => db = memoryDatabase());
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      profiles: profiles,
      dictation: dictation,
      shared: shared,
      db: db,
      extra: cardDataOverrides(db: db, tutor: tutor),
    );
  }

  Future<GapEntry> captured(String text, {GapSuggestion? suggestion}) async {
    final gaps = DriftGapRepository(db);
    final entry = await gaps.capture(
      userId: FakeAuthRepository.id,
      courseId: FakeAssessmentRepository.zzCourse.id,
      l1Text: text,
      context: GapContext.daily,
    );
    if (suggestion != null) await gaps.saveSuggestion(entry.id, suggestion);
    return entry;
  }

  testWidgets('captured, suggested, and made a card', (tester) async {
    await open(tester);
    await tapText(tester, trStrings.gapCaptureButton);
    expect(find.byType(GapCaptureScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'canım sıkıldı');
    await tapText(tester, trStrings.gapContextPair);
    await tapText(tester, trStrings.gapCaptureSave);

    expect(find.byType(GapEntryScreen), findsOneWidget);
    expect(find.text('canım sıkıldı'), findsOneWidget);
    expect(find.text("Let's go out, I'm bored."), findsWidgets);
    expect(find.text('I am bored. We can go out.'), findsWidgets);
    expect(
      find.text(trStrings.gapEntryChunkLine('go out', 'dışarı çıkmak')),
      findsOneWidget,
    );
    final request = tutor.gapAsked.single;
    expect(request.l1Text, 'canım sıkıldı');
    expect(request.context, GapContext.pair);

    await tapText(tester, trStrings.gapEntryAddToCards);
    expect(find.text(trStrings.gapEntryCarded), findsOneWidget);
    final items = await tester.runAsync(
      () => db.select(db.personalItems).get(),
    );
    // A2: the card asks for the simple version; the phrase is its own card.
    expect(items!.map((i) => (i.kind, i.textL2)), [
      ('sentence', 'I am bored. We can go out.'),
      ('chunk', 'go out'),
    ]);
    expect(items.first.variants, ["Let's go out, I'm bored."]);
  });

  testWidgets('said aloud, the words are written in', (tester) async {
    await open(tester);
    await tapText(tester, trStrings.gapCaptureButton);
    await listen(tester);
    expect(find.text(trStrings.gapCaptureListening), findsOneWidget);
    await stop(tester);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'canım sıkıldı');
    expect(dictation.starts, 1);

    dictation.stopFailure = DictationFailure.nothingHeard;
    await listen(tester);
    await stop(tester);
    expect(find.text(trStrings.dictationFailureNothingHeard), findsOneWidget);
    expect(field.controller!.text, 'canım sıkıldı');
  });

  testWidgets('without audio consent there is only the keyboard', (
    tester,
  ) async {
    profiles.audioConsent = false;
    await open(tester);
    await tapText(tester, trStrings.gapCaptureButton);
    expect(find.text(trStrings.gapCaptureDictate), findsNothing);
  });

  testWidgets('a suggestion that cannot come waits for another try', (
    tester,
  ) async {
    tutor.suggestion = null;
    await open(tester);
    await tapText(tester, trStrings.gapCaptureButton);
    await tester.enterText(find.byType(TextField).first, 'yarın görüşürüz');
    await tapText(tester, trStrings.gapCaptureSave);
    expect(find.text(trStrings.gapEntryPending), findsOneWidget);

    tutor.suggestion = gapSuggestion(simple: 'See you tomorrow.');
    await tapText(tester, trStrings.gapEntryRetry);
    expect(find.text('See you tomorrow.'), findsWidgets);
  });

  testWidgets('the list asks again for what waits, and keeps the rest', (
    tester,
  ) async {
    await open(tester);
    await tester.runAsync(() async {
      await captured(
        'bir şey',
        suggestion: gapSuggestion(simple: 'Something.'),
      );
      await captured('bekleyen');
    });
    await tapText(tester, trStrings.tabPractice);
    await tapText(tester, trStrings.practiceGapsTitle);
    expect(find.byType(GapListScreen), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(tutor.gapAsked.map((r) => r.l1Text), ['bekleyen']);
    expect(find.text('Something.'), findsOneWidget);
    expect(find.text('I am bored. We can go out.'), findsOneWidget);

    await tapText(tester, 'bir şey');
    await tapText(tester, trStrings.gapEntryDismiss);
    expect(find.text(trStrings.gapEntryDismissed), findsOneWidget);
    // The list underneath has a back button of its own.
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await tapText(tester, trStrings.gapListDismissed);
    expect(find.text('bir şey'), findsOneWidget);
    await tapText(tester, trStrings.gapListCarded);
    expect(find.text(trStrings.gapListEmptyCarded), findsOneWidget);
  });

  testWidgets('text shared from another app opens a capture', (tester) async {
    final shared = FakeSharedTextSource(first: '  Bu gece dışarı çıkalım mı  ');
    await open(tester, shared: shared);
    expect(find.byType(GapCaptureScreen), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'Bu gece dışarı çıkalım mı');
    final media = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, trStrings.gapContextMedia),
    );
    expect(media.selected, isTrue);
    expect(shared.first, isNull, reason: 'taken once');
  });

  testWidgets('every page fits a small phone at double text size', (
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

    await open(tester);
    await tapText(tester, trStrings.gapCaptureButton);
    await check();
    await tester.enterText(find.byType(TextField).first, 'canım sıkıldı');
    await tapText(tester, trStrings.gapCaptureSave);
    await check();
    await tapText(tester, trStrings.gapEntryAddToCards);
    await check();
    handle.dispose();
  });
}
