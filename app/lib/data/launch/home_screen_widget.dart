import 'package:home_widget/home_widget.dart';

/// What the home screen widget and the quick settings tile show (docs/09
/// §9). The texts come from the ARB file, written by the app; the widget
/// shows `line` on `day` only, `open` on any other day.
typedef WidgetTexts = ({
  String line,
  String open,
  String capture,

  /// The learner's day, `yyyy-MM-dd` where they are.
  String day,
});

/// The home screen widget of this platform.
abstract interface class HomeScreenWidget {
  /// Writes [texts] and redraws the widget.
  Future<void> show(WidgetTexts texts);
}

/// [HomeScreenWidget] on `home_widget` (Android `TodayWidgetProvider`).
class AndroidHomeScreenWidget implements HomeScreenWidget {
  new();

  /// The receiver's class (android `TodayWidgetProvider.kt`); the package
  /// is the Kotlin namespace, whatever the application id.
  static const provider = 'com.dilbaz.dilbaz_app.TodayWidgetProvider';

  /// Keys read by the widget and the tile (android `AppLinks.kt`).
  static const lineKey = 'today_line';
  static const dayKey = 'today_day';
  static const openKey = 'today_open';
  static const captureKey = 'capture_label';

  WidgetTexts? _shown;

  @override
  Future<void> show(WidgetTexts texts) async {
    // The same texts again redraw nothing.
    if (texts == _shown) return;
    _shown = texts;
    await HomeWidget.saveWidgetData<String>(lineKey, texts.line);
    await HomeWidget.saveWidgetData<String>(dayKey, texts.day);
    await HomeWidget.saveWidgetData<String>(openKey, texts.open);
    await HomeWidget.saveWidgetData<String>(captureKey, texts.capture);
    await HomeWidget.updateWidget(qualifiedAndroidName: provider);
  }
}

/// Platforms without a home screen widget.
class NoHomeScreenWidget implements HomeScreenWidget {
  const new();

  @override
  Future<void> show(WidgetTexts texts) async {}
}
