import 'package:home_widget/home_widget.dart';

/// Where the home screen widget and the quick settings tile open the app
/// (A19, docs/09 §9): the card session or the "Söyleyemedim" capture.
enum AppShortcut {
  cards('cards'),
  capture('capture');

  new(this.host);

  /// The host of its link: `dilbaz://<host>` (android `AppLinks.kt`).
  final String host;

  static const scheme = 'dilbaz';

  /// The shortcut of [link]; null for any other link.
  static AppShortcut? of(Uri? link) {
    if (link == null || link.scheme != scheme) return null;
    for (final shortcut in values) {
      if (shortcut.host == link.host) return shortcut;
    }
    return null;
  }
}

/// The links the app was opened with from its widget or tile.
abstract interface class ShortcutSource {
  /// The link the app was started with, if any.
  Future<Uri?> initial();

  /// Links that come while the app runs.
  Stream<Uri?> links();
}

/// [ShortcutSource] on `home_widget` (Android).
class HomeWidgetShortcutSource implements ShortcutSource {
  const new();

  @override
  Future<Uri?> initial() => HomeWidget.initiallyLaunchedFromHomeWidget();

  @override
  Stream<Uri?> links() => HomeWidget.widgetClicked;
}

/// Platforms without a widget or a tile.
class NoShortcutSource implements ShortcutSource {
  const new();

  @override
  Future<Uri?> initial() async => null;

  @override
  Stream<Uri?> links() => const Stream.empty();
}
