import 'dart:async';

import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/features/settings/application/microphone_check_controller.dart';
import 'package:dilbaz_app/features/settings/application/microphone_check_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The calm text for a speech [failure].
String speechFailureText(AppLocalizations l10n, SpeechFailure failure) =>
    switch (failure) {
      SpeechFailure.network => l10n.speechFailureNetwork,
      SpeechFailure.unavailable => l10n.speechFailureUnavailable,
      SpeechFailure.quota => l10n.speechFailureQuota,
      SpeechFailure.busy => l10n.speechFailureBusy,
      SpeechFailure.badAudio => l10n.speechFailureBadAudio,
      SpeechFailure.unknown => l10n.speechFailureUnknown,
    };

/// The calm text for a recording [failure].
String recordFailureText(AppLocalizations l10n, RecordFailure failure) =>
    switch (failure) {
      RecordFailure.permission => l10n.recordFailurePermission,
      RecordFailure.unsupported => l10n.recordFailureUnsupported,
      RecordFailure.device => l10n.recordFailureDevice,
    };

/// Records a sentence and shows what the recognizer heard. Nothing is
/// kept (docs/08-speech.md §5.1).
class MicrophoneCheckScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(microphoneCheckControllerProvider.notifier);
    final state = ref.watch(microphoneCheckControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.microphoneCheckTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              state is MicrophoneCheckNoConsent
                  ? l10n.microphoneCheckNoConsent
                  : l10n.microphoneCheckBody,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            if (state is MicrophoneCheckRecording) ...[
              const _LevelMeter(),
              const SizedBox(height: 16),
            ],
            switch (state) {
              MicrophoneCheckReady() => FilledButton.icon(
                style: _large,
                onPressed: () => unawaited(controller.record()),
                icon: const Icon(Icons.mic),
                label: Text(l10n.microphoneCheckRecord),
              ),
              MicrophoneCheckRecording() => FilledButton.icon(
                style: _large,
                onPressed: () => unawaited(controller.stop()),
                icon: const Icon(Icons.stop),
                label: Text(l10n.microphoneCheckStop),
              ),
              MicrophoneCheckRecognizing() => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 16,
                children: [
                  const CircularProgressIndicator(),
                  Text(l10n.microphoneCheckRecognizing),
                ],
              ),
              MicrophoneCheckNoConsent() || null => const SizedBox.shrink(),
            },
            const SizedBox(height: 24),
            if (state case MicrophoneCheckReady(
              :final heard,
              :final failure,
              :final recordFailure,
            ))
              ..._result(context, heard?.text, failure, recordFailure),
          ],
        ),
      ),
    );
  }

  static final ButtonStyle _large = FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(64),
  );

  List<Widget> _result(
    BuildContext context,
    String? heard,
    SpeechFailure? failure,
    RecordFailure? recordFailure,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final problem = switch ((failure, recordFailure)) {
      (final SpeechFailure failure, _) => speechFailureText(l10n, failure),
      (_, final RecordFailure failure) => recordFailureText(l10n, failure),
      _ => null,
    };
    if (problem != null) {
      return [
        Row(
          spacing: 8,
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.error),
            Expanded(child: Text(problem)),
          ],
        ),
      ];
    }
    if (heard == null) return const [];
    return [
      Text(l10n.microphoneCheckHeard, style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        heard.isEmpty ? l10n.microphoneCheckNothing : heard,
        style: theme.textTheme.headlineSmall,
      ),
    ];
  }
}

class _LevelMeter extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(microphoneLevelProvider).value ?? 0;
    return LinearProgressIndicator(
      value: level,
      minHeight: 8,
      semanticsLabel: context.l10n.microphoneCheckLevel,
    );
  }
}
