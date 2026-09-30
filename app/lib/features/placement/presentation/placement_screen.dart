import 'dart:async';

import 'package:dilbaz_app/features/placement/application/placement_controller.dart';
import 'package:dilbaz_app/features/placement/application/placement_state.dart';
import 'package:dilbaz_app/features/placement/presentation/views/listening_view.dart';
import 'package:dilbaz_app/features/placement/presentation/views/overview_view.dart';
import 'package:dilbaz_app/features/placement/presentation/views/part_intro_view.dart';
import 'package:dilbaz_app/features/placement/presentation/views/question_view.dart';
import 'package:dilbaz_app/features/placement/presentation/views/report_view.dart';
import 'package:dilbaz_app/features/placement/presentation/views/word_view.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The placement test (A24, docs/06-assessment.md §2). Leaving keeps the
/// parts that were finished; nothing is shown as right or wrong until the
/// report at the end.
class PlacementScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    ref.listen(placementControllerProvider, (_, next) {
      // Left before a part was finished: nothing to report.
      if (next case AsyncData(value: PlacementDone(report: null))) {
        if (context.canPop()) context.pop();
      }
    });
    final state = ref.watch(placementControllerProvider);
    final inTest = switch (state) {
      AsyncData(
        value: PlacementPartIntro() ||
            PlacementWord() ||
            PlacementQuestion() ||
            PlacementListening(),
      ) =>
        true,
      _ => false,
    };

    Future<void> leave() async {
      if (inTest && !await _confirmLeave(context)) return;
      await ref.read(placementControllerProvider.notifier).leave();
    }

    final saving = switch (state) {
      AsyncData(value: PlacementSaving()) => true,
      _ => false,
    };
    return PopScope(
      canPop: !inTest && !saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inTest) unawaited(leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.placementTitle),
          leading: switch (state) {
            AsyncData(value: PlacementSaving() || PlacementDone()) => null,
            _ => CloseButton(
              onPressed: inTest ? () => unawaited(leave()) : null,
            ),
          },
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: switch (state) {
            AsyncData(:final value) => switch (value) {
              PlacementUnavailable() => _Note(text: l10n.placementUnavailable),
              PlacementOverview(:final parts) => OverviewView(parts: parts),
              PlacementPartIntro(:final part) => PartIntroView(part: part),
              final PlacementWord word => WordView(state: word),
              final PlacementQuestion question => QuestionView(state: question),
              final PlacementListening listening => ListeningView(
                state: listening,
              ),
              PlacementSaving() => _Busy(text: l10n.placementSaving),
              PlacementDone(:final report?) => ReportView(report: report),
              PlacementDone() => const _Busy(),
            },
            AsyncError() => _Note(text: l10n.placementUnavailable),
            AsyncLoading() => const _Busy(),
          },
        ),
      ),
    );
  }

  static Future<bool> _confirmLeave(BuildContext context) async {
    final l10n = context.l10n;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.placementLeaveTitle),
        content: Text(l10n.placementLeaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.placementLeaveCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.placementLeaveConfirm),
          ),
        ],
      ),
    );
    return leave ?? false;
  }
}

class _Busy extends StatelessWidget {
  const new({this.text});

  final String? text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        const CircularProgressIndicator(),
        if (text case final text?) Text(text),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ),
  );
}
