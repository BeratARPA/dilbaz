import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/features/monthly/application/monthly_invitation.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Today's invitation to the monthly speaking test, on the first days of
/// the month (docs/05 §6, docs/06 §3). An invitation, never a demand
/// (I-14).
class MonthlyInvitationCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(monthlyInvitedProvider)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card.filled(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text(l10n.monthlyInviteTitle, style: theme.textTheme.titleMedium),
              Text(l10n.monthlyInviteBody),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: ref
                        .read(monthlyInvitationDismissedProvider.notifier)
                        .dismiss,
                    child: Text(l10n.monthlyInviteLater),
                  ),
                  FilledButton(
                    onPressed: () async {
                      await context.push(AppRoutes.monthly);
                      // A test taken this month closes the invitation.
                      ref.invalidate(monthlyOpenProvider);
                    },
                    child: Text(l10n.monthlyInviteStart),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
