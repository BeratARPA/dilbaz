import 'dart:async';

import 'package:dilbaz_app/app/routes.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/data/speech/dictation.dart';
import 'package:dilbaz_app/features/gap_journal/application/gap_capture_controller.dart';
import 'package:dilbaz_app/features/gap_journal/presentation/gap_texts.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Capture page of "Söyleyemediklerim" (A19, docs/09 §5.5): what the
/// learner could not say, typed or said in their own language, and where
/// it came up. Text shared from another app arrives here ([sharedText]).
class GapCaptureScreen extends ConsumerStatefulWidget {
  const new({this.sharedText, super.key});

  /// Text shared from another app (Android share menu).
  final String? sharedText;

  @override
  ConsumerState<GapCaptureScreen> createState() => _GapCaptureScreenState();
}

class _GapCaptureScreenState extends ConsumerState<GapCaptureScreen> {
  late final _text = TextEditingController(text: widget.sharedText);
  final _note = TextEditingController();
  late GapContext _context = widget.sharedText == null
      ? GapContext.daily
      : GapContext.media;

  @override
  void dispose() {
    _text.dispose();
    _note.dispose();
    super.dispose();
  }

  GapCaptureController get _controller =>
      ref.read(gapCaptureControllerProvider.notifier);

  Future<void> _save() async {
    final id = await _controller.save(
      text: _text.text,
      context: _context,
      note: _note.text,
    );
    if (id != null && mounted) {
      context.pushReplacement(AppRoutes.gapEntry(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    ref.listen(gapCaptureControllerProvider, (previous, next) {
      final heard = next.value;
      if (heard?.heard == null ||
          heard!.heardCount == previous?.value?.heardCount) {
        return;
      }
      final before = _text.text.trimRight();
      _text.text = before.isEmpty ? heard.heard! : '$before ${heard.heard}';
    });
    final state = ref.watch(gapCaptureControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.gapCaptureTitle)),
      body: SafeArea(
        child: state == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.gapCaptureIntro,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _text,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 300,
                      enabled: !state.listening,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: l10n.gapCaptureTextLabel,
                      ),
                    ),
                    if (state.canDictate) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: state.listening
                            ? FilledButton.icon(
                                onPressed: () =>
                                    unawaited(_controller.stopDictation()),
                                icon: const Icon(Icons.stop),
                                label: Text(l10n.gapCaptureStop),
                              )
                            : OutlinedButton.icon(
                                onPressed: () =>
                                    unawaited(_controller.startDictation()),
                                icon: const Icon(Icons.mic_none),
                                label: Text(l10n.gapCaptureDictate),
                              ),
                      ),
                      if (state.listening) ...[
                        const SizedBox(height: 8),
                        Text(l10n.gapCaptureListening),
                        const LinearProgressIndicator(),
                      ],
                    ],
                    if (state.failure case final failure?) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 8,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          Expanded(
                            child: Text(dictationFailureText(l10n, failure)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      l10n.gapCaptureContext,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in GapContext.values)
                          ChoiceChip(
                            label: Text(gapContextText(l10n, option)),
                            selected: _context == option,
                            onSelected: (_) =>
                                setState(() => _context = option),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _note,
                      maxLength: 200,
                      decoration: InputDecoration(
                        labelText: l10n.gapCaptureNoteLabel,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ListenableBuilder(
                        listenable: _text,
                        builder: (context, _) => FilledButton(
                          onPressed:
                              _text.text.trim().isEmpty ||
                                  state.saving ||
                                  !state.ready
                              ? null
                              : () => unawaited(_save()),
                          child: Text(l10n.gapCaptureSave),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The calm text for a dictation [failure].
String dictationFailureText(AppLocalizations l10n, DictationFailure failure) =>
    switch (failure) {
      DictationFailure.permission => l10n.dictationFailurePermission,
      DictationFailure.unavailable => l10n.dictationFailureUnavailable,
      DictationFailure.network => l10n.dictationFailureNetwork,
      DictationFailure.quota => l10n.dictationFailureQuota,
      DictationFailure.busy => l10n.dictationFailureBusy,
      DictationFailure.nothingHeard => l10n.dictationFailureNothingHeard,
      DictationFailure.unknown => l10n.dictationFailureUnknown,
    };
