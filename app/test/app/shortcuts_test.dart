import 'package:dilbaz_app/app/home_shell.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/launch/home_screen_widget.dart';
import 'package:dilbaz_app/features/cards/presentation/card_session_screen.dart';
import 'package:dilbaz_app/features/gap_journal/presentation/gap_capture_screen.dart';
import 'package:dilbaz_app/features/today/application/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/launch/launch_test.dart' show FakeShortcutSource;
import '../helpers/card_fixture.dart';
import '../helpers/pack_fixture.dart';
import '../helpers/pump_app.dart';

/// The widget as the app writes it.
class FakeHomeScreenWidget implements HomeScreenWidget {
  final shown = <WidgetTexts>[];

  @override
  Future<void> show(WidgetTexts texts) async => shown.add(texts);
}

TodayView view({
  int reviews = 0,
  int newItems = 0,
  Duration estimate = Duration.zero,
  bool enough = false,
}) => TodayView(
  greeting: TodayGreeting.day,
  dailyBudget: const Duration(minutes: 30),
  reviews: reviews,
  newItems: newItems,
  estimate: estimate,
  enough: enough,
  minimumDay: false,
  backlog: false,
  reviewedToday: 0,
  introducedToday: 0,
  spentToday: Duration.zero,
  daysThisWeek: 0,
  weeklyGoal: 5,
);

void main() {
  late AppDatabase db;

  Future<void> open(
    WidgetTester tester, {
    FakeShortcutSource? shortcuts,
    FakeHomeScreenWidget? homeWidget,
  }) async {
    await tester.runAsync(() async {
      db = memoryDatabase();
      await installCardPacks(db);
    });
    addTearDown(db.close);
    await tester.pumpDilbazApp(
      db: db,
      shortcuts: shortcuts,
      homeWidget: homeWidget,
      extra: cardDataOverrides(db: db, tutor: FakeTutorRepository()),
    );
  }

  testWidgets('the tile opens the capture page (A19)', (tester) async {
    await open(
      tester,
      shortcuts: FakeShortcutSource(first: Uri.parse('dilbaz://capture')),
    );
    expect(find.byType(GapCaptureScreen), findsOneWidget);
  });

  testWidgets('the widget opens the cards while the app runs', (tester) async {
    final shortcuts = FakeShortcutSource();
    await open(tester, shortcuts: shortcuts);
    expect(find.byType(CardSessionScreen), findsNothing);
    shortcuts.clicked.add(Uri.parse('dilbaz://cards'));
    await tester.pumpAndSettle();
    expect(find.byType(CardSessionScreen), findsOneWidget);
  });

  testWidgets("the widget gets today's line in the ARB's words", (
    tester,
  ) async {
    final homeWidget = FakeHomeScreenWidget();
    await open(tester, homeWidget: homeWidget);
    final texts = homeWidget.shown.last;
    expect(texts.line, startsWith('Bugün: '));
    expect(texts.open, trStrings.widgetOpen);
    expect(texts.capture, trStrings.gapCaptureButton);
    final now = cardNow.toLocal();
    expect(
      texts.day,
      '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}',
    );
  });

  test('the line: cards and minutes, nothing planned, or enough', () {
    final at = DateTime.utc(2026, 3, 5, 12);
    expect(
      widgetTexts(
        trStrings,
        view(reviews: 3, newItems: 2, estimate: const Duration(seconds: 250)),
        at,
      ).line,
      trStrings.widgetToday(5, 5),
    );
    expect(
      widgetTexts(
        trStrings,
        view(reviews: 1, estimate: const Duration(seconds: 10)),
        at,
      ).line,
      trStrings.widgetToday(1, 1),
    );
    expect(widgetTexts(trStrings, view(), at).line, trStrings.widgetNoCards);
    expect(
      widgetTexts(trStrings, view(reviews: 4, enough: true), at).line,
      trStrings.todayEnoughTitle,
    );
  });
}
