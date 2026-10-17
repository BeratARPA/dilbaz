import 'dart:async';
import 'dart:io';

import 'package:dilbaz_app/data/launch/app_shortcuts.dart';
import 'package:dilbaz_app/data/launch/home_screen_widget.dart';
import 'package:dilbaz_app/data/launch/launch_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Links from the widget or the tile.
class FakeShortcutSource implements ShortcutSource {
  new({this.first});

  Uri? first;
  final clicked = StreamController<Uri?>.broadcast();

  @override
  Future<Uri?> initial() async => first;

  @override
  Stream<Uri?> links() => clicked.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the widget and the tile open the cards or the capture', () {
    expect(AppShortcut.of(Uri.parse('dilbaz://cards')), AppShortcut.cards);
    expect(AppShortcut.of(Uri.parse('dilbaz://capture')), AppShortcut.capture);
    for (final other in ['dilbaz://other', 'https://cards', '']) {
      expect(AppShortcut.of(Uri.parse(other)), isNull, reason: other);
    }
    expect(AppShortcut.of(null), isNull);
  });

  test('the first link, then those that come; others are not', () async {
    final source = FakeShortcutSource(first: Uri.parse('dilbaz://capture'));
    final container = ProviderContainer(
      overrides: [shortcutSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final seen = <AppShortcut>[];
    container.listen(shortcutsProvider, (_, next) {
      if (next case AsyncData(:final value)) seen.add(value);
    });
    final pending = container.read(pendingShortcutProvider.notifier);
    await pumpEventQueue();
    expect(container.read(pendingShortcutProvider), AppShortcut.capture);
    expect(pending.take(), AppShortcut.capture);
    expect(pending.take(), isNull, reason: 'handed over once');
    source.clicked
      ..add(Uri.parse('dilbaz://nothing'))
      ..add(Uri.parse('dilbaz://cards'));
    await pumpEventQueue();
    expect(seen, [AppShortcut.capture, AppShortcut.cards]);
  });

  test(
    'the texts go to the widget once; the same again redraw nothing',
    () async {
      const channel = MethodChannel('home_widget');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final widget = AndroidHomeScreenWidget();
      const texts = (
        line: 'Bugün: 3 kart · ~2 dk',
        open: 'Bugünün kartlarını gör',
        capture: 'Söyleyemedim',
        day: '2026-10-17',
      );
      await widget.show(texts);
      await widget.show(texts);
      expect(calls.map((c) => c.method), [
        'saveWidgetData',
        'saveWidgetData',
        'saveWidgetData',
        'saveWidgetData',
        'updateWidget',
      ]);
      expect(
        {
          for (final call in calls.take(4))
            (call.arguments as Map)['id']: (call.arguments as Map)['data'],
        },
        {
          'today_line': texts.line,
          'today_day': texts.day,
          'today_open': texts.open,
          'capture_label': texts.capture,
        },
      );
      expect(
        (calls.last.arguments as Map)['qualifiedAndroidName'],
        AndroidHomeScreenWidget.provider,
      );
    },
  );

  test("Android's own texts are those of the ARB file", () {
    final xml = File('android/app/src/main/res/values/strings.xml')
        .readAsStringSync();
    String string(String name) =>
        RegExp('<string name="$name">([^<]*)</string>')
            .firstMatch(xml)!
            .group(1)!;
    expect(string('capture_tile'), trStrings.gapCaptureButton);
    expect(string('today_widget_description'), trStrings.widgetDescription);
    expect(string('today_widget_open'), trStrings.widgetOpen);
  });

  test('the Kotlin side reads the keys the app writes', () {
    final links = File(
      'android/app/src/main/kotlin/com/dilbaz/dilbaz_app/AppLinks.kt',
    ).readAsStringSync();
    for (final key in [
      AndroidHomeScreenWidget.lineKey,
      AndroidHomeScreenWidget.dayKey,
      AndroidHomeScreenWidget.openKey,
      AndroidHomeScreenWidget.captureKey,
      for (final shortcut in AppShortcut.values)
        '${AppShortcut.scheme}://${shortcut.host}',
    ]) {
      expect(links, contains('"$key"'), reason: key);
    }
    final provider = File(
      'android/app/src/main/kotlin/com/dilbaz/dilbaz_app/TodayWidgetProvider.kt',
    ).readAsStringSync();
    expect(provider, contains('package com.dilbaz.dilbaz_app\n'));
    expect(provider, contains('class TodayWidgetProvider'));
    expect(
      AndroidHomeScreenWidget.provider,
      'com.dilbaz.dilbaz_app.TodayWidgetProvider',
    );
  });
}
