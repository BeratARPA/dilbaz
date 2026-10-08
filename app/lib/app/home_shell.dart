import 'dart:async';

import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/data/share/share_providers.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Bottom bar with four tabs and the "Söyleyemedim" button that is visible on
/// every tab (docs/09-ux-motivation.md §4). Text shared from another app
/// opens a capture here (A19).
class HomeShell extends ConsumerWidget {
  const new({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
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
