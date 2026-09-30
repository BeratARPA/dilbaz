import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/features/placement/application/placement_invitation.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Today's invitation to the placement test, while the course has none
/// (docs/09-ux-motivation.md §5.1). An invitation, never a demand (I-14).
class PlacementInvitationCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(placementInvitedProvider)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(l10n.placementInviteTitle, style: theme.textTheme.titleMedium),
            Text(l10n.placementInviteBody),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: ref
                      .read(placementInvitationDismissedProvider.notifier)
                      .dismiss,
                  child: Text(l10n.placementInviteLater),
                ),
                FilledButton(
                  onPressed: () => context.push(AppRoutes.placement),
                  child: Text(l10n.placementInviteStart),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
