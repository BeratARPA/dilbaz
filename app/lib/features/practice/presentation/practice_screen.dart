import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Practice tab: every activity grouped by type (docs/09 §4). Cards come
/// first; the others follow with their tasks.
class PracticeScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabPractice)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card.outlined(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.push(AppRoutes.cards),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  spacing: 16,
                  children: [
                    Icon(
                      Icons.style_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          Text(
                            l10n.practiceCardsTitle,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            l10n.practiceCardsBody,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(l10n.practiceMoreSoon, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
