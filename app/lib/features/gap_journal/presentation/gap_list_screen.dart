import 'dart:async';

import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/features/gap_journal/application/gap_entry_controller.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// "Söyleyemediklerim" (A19, docs/09 §5.5): new, carded and dismissed
/// captures.
class GapListScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<GapListScreen> createState() => _GapListScreenState();
}

class _GapListScreenState extends ConsumerState<GapListScreen> {
  GapStatus _status = GapStatus.fresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = ref.watch(gapEntriesProvider).value ?? const [];
    final shown = [
      for (final entry in entries)
        if (entry.status == _status) entry,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.practiceGapsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.gapListAdd,
            onPressed: () => unawaited(context.push(AppRoutes.gapCapture)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<GapStatus>(
                segments: [
                  ButtonSegment(
                    value: GapStatus.fresh,
                    label: Text(l10n.gapListFresh),
                  ),
                  ButtonSegment(
                    value: GapStatus.carded,
                    label: Text(l10n.gapListCarded),
                  ),
                  ButtonSegment(
                    value: GapStatus.dismissed,
                    label: Text(l10n.gapListDismissed),
                  ),
                ],
                selected: {_status},
                showSelectedIcon: false,
                onSelectionChanged: (selected) =>
                    setState(() => _status = selected.first),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(switch (_status) {
                          GapStatus.fresh => l10n.gapListEmptyFresh,
                          GapStatus.carded => l10n.gapListEmptyCarded,
                          GapStatus.dismissed => l10n.gapListEmptyDismissed,
                        }, textAlign: TextAlign.center),
                      ),
                    )
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = shown[index];
                        return ListTile(
                          title: Text(entry.l1Text),
                          subtitle: Text(
                            entry.suggestion?.l2Simple ?? l10n.gapListWaiting,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => unawaited(
                            context.push(AppRoutes.gapEntry(entry.id)),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
