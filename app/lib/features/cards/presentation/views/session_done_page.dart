import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The end of a card session: what was done, in concrete numbers
/// (docs/09 §2). No score.
class SessionDonePage extends StatelessWidget {
  const new({required this.reviewed, required this.introduced, super.key});

  final int reviewed;
  final int introduced;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.cardsDoneTitle,
              style: theme.textTheme.headlineSmall,
            ),
          ),
          if (reviewed > 0)
            Text(
              l10n.cardsDoneReviewed(reviewed),
              style: theme.textTheme.bodyLarge,
            ),
          if (introduced > 0)
            Text(
              l10n.cardsDoneIntroduced(introduced),
              style: theme.textTheme.bodyLarge,
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => context.pop(),
              child: Text(l10n.cardsClose),
            ),
          ),
        ],
      ),
    );
  }
}
