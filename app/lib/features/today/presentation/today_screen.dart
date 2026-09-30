import 'package:dilbaz_app/features/content/presentation/content_status_view.dart';
import 'package:dilbaz_app/features/placement/presentation/placement_invitation_card.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Today tab: the planner's suggestions (docs/09 §5.2).
class TodayScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabToday)),
      body: ContentStatusView(
        ready: (context, content) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const PlacementInvitationCard(),
            const SizedBox(height: 24),
            Text(l10n.sectionInPreparation, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              l10n.contentReady(
                content.words,
                content.chunks,
                content.sentences,
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
