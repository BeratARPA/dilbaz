import 'package:dilbaz_app/data/launch/app_shortcuts.dart';
import 'package:dilbaz_app/data/launch/home_screen_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'launch_providers.g.dart';

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// The widget's and the tile's links on this platform; tests override it.
@Riverpod(keepAlive: true)
ShortcutSource shortcutSource(Ref ref) =>
    _android ? const HomeWidgetShortcutSource() : const NoShortcutSource();

/// The home screen widget of this platform; tests override it.
@Riverpod(keepAlive: true)
HomeScreenWidget homeScreenWidget(Ref ref) =>
    _android ? AndroidHomeScreenWidget() : const NoHomeScreenWidget();

/// Every shortcut the app is opened with: the first, then the rest.
@Riverpod(keepAlive: true)
Stream<AppShortcut> shortcuts(Ref ref) async* {
  final source = ref.watch(shortcutSourceProvider);
  if (AppShortcut.of(await source.initial()) case final first?) yield first;
  await for (final link in source.links()) {
    if (AppShortcut.of(link) case final shortcut?) yield shortcut;
  }
}

/// A shortcut that waits for the home screen: before sign-in and the
/// welcome flow there is nowhere to open it.
@Riverpod(keepAlive: true)
class PendingShortcut extends _$PendingShortcut {
  @override
  AppShortcut? build() {
    ref.listen(shortcutsProvider, (_, next) {
      if (next case AsyncData(:final value)) state = value;
    });
    return null;
  }

  /// The waiting shortcut, handed over once.
  AppShortcut? take() {
    final shortcut = state;
    state = null;
    return shortcut;
  }
}
