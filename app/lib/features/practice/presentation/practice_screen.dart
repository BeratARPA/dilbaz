import 'dart:async';

import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Practice tab: every activity grouped by type (docs/09 §4). Cards and
/// "Söyleyemediklerim" come first; the others follow with their tasks.
class PracticeScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabPractice)),
      // A short list, built whole: every activity can be found and reached.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Activity(
              icon: Icons.style_outlined,
              title: l10n.practiceCardsTitle,
              body: l10n.practiceCardsBody,
              route: AppRoutes.cards,
            ),
            const SizedBox(height: 12),
            _Activity(
              icon: Icons.record_voice_over_outlined,
              title: l10n.practiceGapsTitle,
              body: l10n.practiceGapsBody,
              route: AppRoutes.gaps,
            ),
            const SizedBox(height: 12),
            _Activity(
              icon: Icons.mic_none,
              title: l10n.practiceSpeakingTitle,
              body: l10n.practiceSpeakingBody,
              route: AppRoutes.speaking,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.practiceMoreSoon,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Activity extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.body,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String body;
  final String route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(context.push(route)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            spacing: 16,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    Text(body, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
