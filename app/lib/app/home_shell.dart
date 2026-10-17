import 'dart:async';
import 'dart:math';

import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/launch/app_shortcuts.dart';
import 'package:dilbaz_app/data/launch/home_screen_widget.dart';
import 'package:dilbaz_app/data/launch/launch_providers.dart';
import 'package:dilbaz_app/data/share/share_providers.dart';
import 'package:dilbaz_app/features/notifications/application/invitation_scheduler.dart';
import 'package:dilbaz_app/features/sync/application/sync_controller.dart';
import 'package:dilbaz_app/features/today/application/today_controller.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Bottom bar with four tabs and the "Söyleyemedim" button that is visible on
/// every tab (docs/09-ux-motivation.md §4). Text shared from another app
/// opens a capture here (A19), and so do the home screen widget and the
/// quick settings tile; the widget's line follows today's plan (docs/09
/// §9). While it is up, the device syncs and the daily invitation is kept
/// set ahead.
class HomeShell extends ConsumerWidget {
  const new({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Kept running without rebuilding the shell.
    ref
      ..listen(syncControllerProvider, (_, _) {})
      ..listen(invitationSchedulerProvider, (_, _) {});
    ref.listen(todayProvider, (_, next) {
      if (next case AsyncData(value: final view?)) {
        unawaited(
          ref
              .read(homeScreenWidgetProvider)
              .show(widgetTexts(l10n, view, ref.read(clockProvider)())),
        );
      }
    });
    if (ref.watch(pendingShortcutProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final shortcut = ref.read(pendingShortcutProvider.notifier).take();
        final route = switch (shortcut) {
          AppShortcut.cards => AppRoutes.cards,
          AppShortcut.capture => AppRoutes.gapCapture,
          null => null,
        };
        if (route != null) unawaited(context.push(route));
      });
    }
    if (ref.watch(pendingShareProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final text = ref.read(pendingShareProvider.notifier).take();
        if (text != null) {
          unawaited(context.push(AppRoutes.gapCapture, extra: text));
        }
      });
    }
    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.gapCapture),
        icon: const Icon(Icons.add),
        label: Text(l10n.gapCaptureButton),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.wb_sunny_outlined),
            selectedIcon: const Icon(Icons.wb_sunny),
            label: l10n.tabToday,
          ),
          NavigationDestination(
            icon: const Icon(Icons.fitness_center_outlined),
            selectedIcon: const Icon(Icons.fitness_center),
            label: l10n.tabPractice,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: l10n.tabTogether,
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            label: l10n.tabProgress,
          ),
        ],
      ),
    );
  }
}

/// The widget's texts for today's [view] at [now] (docs/09 §9): the cards
/// and their time, or that today is done; never a count of what was left
/// undone (I-12).
WidgetTexts widgetTexts(AppLocalizations l10n, TodayView view, DateTime now) {
  final cards = view.reviews + view.newItems;
  final minutes = max(1, (view.estimate.inSeconds / 60).ceil());
  final local = now.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return (
    line: view.enough
        ? l10n.todayEnoughTitle
        : cards == 0
        ? l10n.widgetNoCards
        : l10n.widgetToday(cards, minutes),
    open: l10n.widgetOpen,
    capture: l10n.gapCaptureButton,
    day: '${local.year}-${two(local.month)}-${two(local.day)}',
  );
}
