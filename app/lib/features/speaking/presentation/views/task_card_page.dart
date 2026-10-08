import 'dart:async';

import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The task card (docs/09 §5.6): the task, its phrases and the time to
/// prepare, then the recording with its time and a level meter. Nothing
/// starts by itself when the preparation time is over.
class TaskCardPage extends StatelessWidget {
  const new({
    required this.task,
    required this.recording,
    required this.onStart,
    required this.onStop,
    this.onOtherTask,
    this.header = const [],
    super.key,
  });

  final TaskView task;
  final bool recording;
  final VoidCallback onStart;
  final VoidCallback onStop;

  /// Back to the list; none in a test.
  final VoidCallback? onOtherTask;

  /// Shown above the task, such as its number in a test.
  final List<Widget> header;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          ...header,
          Text(task.title, style: theme.textTheme.titleLarge),
          Text(task.prompt, style: theme.textTheme.bodyLarge),
          if (task.phrases.isNotEmpty) _Phrases(task: task),
          if (recording) ...[
            Text(l10n.speakingListening, textAlign: TextAlign.center),
            _Elapsed(limit: task.limit),
            const _LevelMeter(),
            FilledButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: Text(l10n.speakingStop),
            ),
          ] else ...[
            _Countdown(preparation: task.preparation),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.mic),
              label: Text(l10n.speakingStart),
            ),
            if (onOtherTask case final otherTask?)
              TextButton(
                onPressed: otherTask,
                child: Text(l10n.speakingOtherTask),
              ),
          ],
        ],
      ),
    );
  }
}

class _Phrases extends StatefulWidget {
  const new({required this.task});

  final TaskView task;

  @override
  State<_Phrases> createState() => _PhrasesState();
}

class _PhrasesState extends State<_Phrases> {
  late bool _open = widget.task.phrasesOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (!_open) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => setState(() => _open = true),
          child: Text(l10n.speakingShowPhrases),
        ),
      );
    }
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(l10n.speakingPhrases, style: theme.textTheme.titleSmall),
            for (final (:phrase, :meaning) in widget.task.phrases)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(phrase, style: theme.textTheme.bodyLarge),
                  if (meaning.isNotEmpty)
                    Text(meaning, style: theme.textTheme.bodySmall),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The time left to prepare, by the level's scaffolds (docs/02 §3).
class _Countdown extends StatefulWidget {
  const new({required this.preparation});

  final Duration preparation;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late int _left = widget.preparation.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_left > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _left--);
        if (_left <= 0) timer.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Text(
      _left > 0
          ? l10n.speakingPreparation(_left)
          : l10n.speakingPreparationOver,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

/// Minutes and seconds, as "1:05".
String clockText(Duration time) =>
    '${time.inMinutes}:${(time.inSeconds % 60).toString().padLeft(2, '0')}';

class _Elapsed extends StatefulWidget {
  const new({required this.limit});

  final Duration limit;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  final _watch = Stopwatch()..start();
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _watch.elapsed > widget.limit
        ? widget.limit
        : _watch.elapsed;
    return Text(
      context.l10n.speakingElapsed(clockText(elapsed), clockText(widget.limit)),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall,
    );
  }
}

class _LevelMeter extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(answerLevelProvider).value ?? 0;
    return ExcludeSemantics(
      child: LinearProgressIndicator(value: level, minHeight: 8),
    );
  }
}
