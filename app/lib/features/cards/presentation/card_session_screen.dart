import 'dart:async';

import 'package:dilbaz_app/features/cards/application/card_session_controller.dart';
import 'package:dilbaz_app/features/cards/application/card_session_state.dart';
import 'package:dilbaz_app/features/cards/presentation/views/card_page.dart';
import 'package:dilbaz_app/features/cards/presentation/views/introduction_page.dart';
import 'package:dilbaz_app/features/cards/presentation/views/session_done_page.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A card session over the tabs (A00–A02, docs/09 §5.3). Leaving needs no
/// confirmation: every finished card is already stored, and nothing is
/// owed (I-14).
class CardSessionScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(cardSessionControllerProvider);

    Future<void> leave() async {
      await ref.read(cardSessionControllerProvider.notifier).leave();
      if (context.mounted && context.canPop()) context.pop();
    }

    final progress = switch (state.value) {
      CardSessionIntroduction(:final view) => l10n.cardsProgress(
        view.number,
        view.total,
      ),
      CardSessionCard(:final view) => l10n.cardsProgress(
        view.number,
        view.total,
      ),
      _ => null,
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.cardsTitle),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.cardsLeave,
            onPressed: () => unawaited(leave()),
          ),
          actions: [
            if (progress != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: Text(progress)),
              ),
          ],
        ),
        body: SafeArea(
          child: switch (state) {
            AsyncData(:final value) => switch (value) {
              CardSessionUnavailable() => _Note(text: l10n.cardsUnavailable),
              CardSessionEmpty() => _Note(text: l10n.cardsEmpty),
              CardSessionIntroduction(:final view) => IntroductionPage(
                view: view,
              ),
              CardSessionCard(:final view) => CardPage(view: view),
              CardSessionDone(:final reviewed, :final introduced) =>
                SessionDonePage(reviewed: reviewed, introduced: introduced),
            },
            AsyncError() => _Note(text: l10n.cardsUnavailable),
            AsyncLoading() => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 24,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          FilledButton(
            onPressed: () => context.pop(),
            child: Text(context.l10n.cardsClose),
          ),
        ],
      ),
    ),
  );
}
