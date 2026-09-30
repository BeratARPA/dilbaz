import 'package:dilbaz_app/features/onboarding/presentation/steps/step_header.dart';
import 'package:dilbaz_app/features/placement/application/placement_controller.dart';
import 'package:dilbaz_app/features/placement/application/placement_state.dart';
import 'package:dilbaz_app/features/placement/presentation/views/part_texts.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Before a part: what it asks for. The dictation can be left out by a
/// learner who cannot listen now.
class PartIntroView extends ConsumerWidget {
  const new({required this.part, super.key});

  final PlacementPart part;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(placementControllerProvider.notifier);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepHeader(title: partTitle(l10n, part), body: partIntro(l10n, part)),
          FilledButton(
            onPressed: controller.startPart,
            child: Text(l10n.placementStartPart),
          ),
          if (part == PlacementPart.dictation) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: controller.skipDictation,
              child: Text(l10n.placementSkipDictation),
            ),
          ],
        ],
      ),
    );
  }
}
