import 'package:dilbaz_app/data/repositories/card_feedback_repository.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Sends a report: why, and the learner's note if any.
typedef ReportSender = Future<void> Function(ReportReason reason, String? note);

/// "Bu içerikte hata var" (docs/09-ux-motivation.md §5.3, docs/10 §8): asks
/// why, sends it with [send] and thanks the learner; nothing when they
/// change their mind.
Future<void> askContentReport(BuildContext context, ReportSender send) async {
  final messenger = ScaffoldMessenger.of(context);
  final thanks = context.l10n.reportThanks;
  final report = await showModalBottomSheet<_Report>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _ReportSheet(),
  );
  if (report == null) return;
  await send(report.reason, report.note);
  messenger.showSnackBar(SnackBar(content: Text(thanks)));
}

/// Content the learner can report with a long press. It is a shortcut: the
/// session's app bar has the same action as a button, for everyone and for
/// screen readers.
class ReportOnLongPress extends StatelessWidget {
  const new({required this.onReport, required this.child, super.key});

  final ReportSender onReport;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    excludeFromSemantics: true,
    onLongPress: () => askContentReport(context, onReport),
    child: child,
  );
}

typedef _Report = ({ReportReason reason, String? note});

/// Why the content is wrong, and a note.
class _ReportSheet extends StatefulWidget {
  const new();

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _note = TextEditingController();
  ReportReason? _reason;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  static String _label(AppLocalizations l10n, ReportReason reason) =>
      switch (reason) {
        ReportReason.meaning => l10n.reportReasonMeaning,
        ReportReason.sentence => l10n.reportReasonSentence,
        ReportReason.audio => l10n.reportReasonAudio,
        // A disputed answer is reported from the card's end, not here.
        ReportReason.answer || ReportReason.other => l10n.reportReasonOther,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final reason = _reason;
    // Above the keyboard, and above the system's navigation bar, which the
    // sheet otherwise reaches under.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.reportTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Text(l10n.reportQuestion),
              RadioGroup<ReportReason>(
                groupValue: reason,
                onChanged: (chosen) => setState(() => _reason = chosen),
                child: Column(
                  children: [
                    for (final option in const [
                      ReportReason.meaning,
                      ReportReason.sentence,
                      ReportReason.audio,
                      ReportReason.other,
                    ])
                      RadioListTile<ReportReason>(
                        value: option,
                        title: Text(_label(l10n, option)),
                      ),
                  ],
                ),
              ),
              TextField(
                controller: _note,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.reportNoteLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.reportCancel),
                  ),
                  FilledButton(
                    onPressed: reason == null
                        ? null
                        : () => Navigator.of(context)
                              .pop<_Report>((reason: reason, note: _note.text)),
                    child: Text(l10n.reportSend),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
