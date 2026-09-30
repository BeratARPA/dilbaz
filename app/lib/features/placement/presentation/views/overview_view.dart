import 'package:dilbaz_app/features/placement/application/placement_controller.dart';
import 'package:dilbaz_app/features/placement/application/placement_state.dart';
import 'package:dilbaz_app/features/placement/presentation/views/part_texts.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Before the test: what it is, and what it is not (docs/06 §6).
class OverviewView extends ConsumerWidget {
  const new({required this.parts, super.key});

  final List<PlacementPart> parts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Text(l10n.placementOverviewBody, style: theme.textTheme.bodyLarge),
          for (final (index, part) in parts.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(partLength(l10n, part)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: ref.read(placementControllerProvider.notifier).begin,
              child: Text(l10n.placementBegin),
            ),
          ),
        ],
      ),
    );
  }
}
