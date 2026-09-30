import 'dart:async';

import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/features/content/application/content_controller.dart';
import 'package:dilbaz_app/features/content/application/content_status.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows [ready] once the course's content is on the device; until then a
/// calm note on what is happening, with a way to try again.
class ContentStatusView extends ConsumerWidget {
  const new({required this.ready, super.key});

  final Widget Function(BuildContext context, ContentReady content) ready;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final status = ref.watch(contentControllerProvider);
    void retry() =>
        unawaited(ref.read(contentControllerProvider.notifier).retry());
    return switch (status) {
      AsyncData(value: final ContentReady content) => ready(context, content),
      AsyncData(value: ContentUnavailable(:final failure)) => _Unavailable(
        message: packFailureText(l10n, failure),
        onRetry: retry,
      ),
      AsyncError() => _Unavailable(
        message: l10n.contentFailureUnknown,
        onRetry: retry,
      ),
      AsyncLoading() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            const CircularProgressIndicator(),
            Text(l10n.contentPreparing),
          ],
        ),
      ),
    };
  }
}

/// The calm text for a content [failure].
String packFailureText(AppLocalizations l10n, PackFailure failure) =>
    switch (failure) {
      PackFailure.network => l10n.contentFailureNetwork,
      PackFailure.missing => l10n.contentFailureMissing,
      PackFailure.damaged => l10n.contentFailureDamaged,
      PackFailure.unsupported => l10n.contentFailureUnsupported,
      PackFailure.unknown => l10n.contentFailureUnknown,
    };

class _Unavailable extends StatelessWidget {
  const new({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          Text(message, textAlign: TextAlign.center),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text(context.l10n.contentRetry),
          ),
        ],
      ),
    ),
  );
}
