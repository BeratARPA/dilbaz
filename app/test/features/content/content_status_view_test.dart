import 'dart:async';

import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/features/content/application/content_controller.dart';
import 'package:dilbaz_app/features/content/application/content_status.dart';
import 'package:dilbaz_app/features/content/presentation/content_status_view.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// A controller that answers from a script instead of fetching.
class ScriptedContentController extends ContentController {
  new(this.first, {this.afterRetry = readyContent});

  /// The first status; null keeps the controller loading.
  final ContentStatus? first;
  final ContentStatus afterRetry;
  int retries = 0;

  @override
  Future<ContentStatus> build() =>
      first == null ? Completer<ContentStatus>().future : Future.value(first);

  @override
  Future<void> retry() async {
    retries++;
    state = AsyncData(afterRetry);
  }
}

void main() {
  Future<ScriptedContentController> pumpView(
    WidgetTester tester,
    ContentStatus? first,
  ) async {
    final controller = ScriptedContentController(first);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [contentControllerProvider.overrideWith(() => controller)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          home: Scaffold(
            body: ContentStatusView(
              ready: (context, content) => Text('ready:${content.words}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('says that content is on its way while it is fetched', (
    tester,
  ) async {
    await pumpView(tester, null);

    expect(find.text(trStrings.contentPreparing), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows what the screen builds once content is ready', (
    tester,
  ) async {
    await pumpView(tester, readyContent);

    expect(find.text('ready:600'), findsOneWidget);
    expect(find.text(trStrings.contentPreparing), findsNothing);
  });

  testWidgets('explains calmly and offers to try again', (tester) async {
    final controller = await pumpView(
      tester,
      const ContentStatus.unavailable(PackFailure.network),
    );

    expect(find.text(trStrings.contentFailureNetwork), findsOneWidget);
    expect(find.text('ready:600'), findsNothing);

    await tester.tap(find.text(trStrings.contentRetry));
    await tester.pump();

    expect(controller.retries, 1);
    expect(find.text('ready:600'), findsOneWidget);
  });

  test('every failure has its own text', () {
    final texts = {
      for (final failure in PackFailure.values)
        failure: packFailureText(trStrings, failure),
    };
    expect(texts, {
      PackFailure.network: trStrings.contentFailureNetwork,
      PackFailure.missing: trStrings.contentFailureMissing,
      PackFailure.damaged: trStrings.contentFailureDamaged,
      PackFailure.unsupported: trStrings.contentFailureUnsupported,
      PackFailure.unknown: trStrings.contentFailureUnknown,
    });
    expect(texts.values.toSet(), hasLength(PackFailure.values.length));
  });

  testWidgets('the Today tab tells what the packs hold', (tester) async {
    await tester.pumpDilbazApp();

    expect(find.text(trStrings.contentReady(600, 120, 588)), findsOneWidget);
  });
}
