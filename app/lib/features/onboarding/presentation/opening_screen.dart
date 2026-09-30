import 'package:dilbaz_app/features/onboarding/application/onboarding_gate.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown to a signed-in learner until it is known whether the welcome flow
/// is due. When the server cannot be asked, it offers to ask again.
class OpeningScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final gate = ref.watch(onboardedProvider);
    // Neither waiting nor decided: the server could not be asked.
    final unreachable = !gate.isLoading && gate.value == null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: unreachable
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 16,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 40),
                      Text(
                        l10n.openingUnreachable,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      FilledButton(
                        onPressed: () => ref.invalidate(onboardedProvider),
                        child: Text(l10n.openingRetry),
                      ),
                    ],
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
