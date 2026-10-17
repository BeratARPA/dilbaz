import 'dart:async';
import 'dart:math';

import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:dilbaz_app/features/together/application/together_controller.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shared weekly goal (docs/09 §7, F2-09): one ring, the two partners'
/// days in two colors, the total against the goal. Nobody is ranked: the
/// text says "together", never who did more (I-12). Under it the partner's
/// week in counts, and "tebrik gönder".
class WeekGoal extends ConsumerWidget {
  const new({
    required this.week,
    required this.self,
    required this.partner,
    super.key,
  });

  final TeamWeek week;
  final String self;
  final TeamMember partner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    int days(String id) =>
        week.members.where((m) => m.id == id).firstOrNull?.days ?? 0;
    final mine = days(self);
    final theirs = days(partner.id);
    final total = mine + theirs;
    final goal = max(week.goalDays, 1);
    final them = week.members.where((m) => m.id == partner.id).firstOrNull;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Row(
              spacing: 16,
              children: [
                Semantics(
                  label: l10n.togetherGoal(total, week.goalDays),
                  excludeSemantics: true,
                  child: SizedBox.square(
                    dimension: 72,
                    child: CustomPaint(
                      painter: _Ring(
                        first: mine / goal,
                        second: theirs / goal,
                        firstColor: theme.colorScheme.primary,
                        secondColor: theme.colorScheme.tertiary,
                        track: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.togetherGoal(total, week.goalDays),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (them != null)
              Text(
                l10n.togetherPartnerWeek(
                  partner.name,
                  them.days,
                  them.minutes,
                  them.together,
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => unawaited(_askCheer(context, ref)),
              icon: const Icon(Icons.celebration_outlined),
              label: Text(l10n.cheerSend),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _askCheer(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final chosen = await showModalBottomSheet<CheerKey>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final key in CheerKey.values)
              ListTile(
                title: Text(cheerText(l10n, key)),
                onTap: () => Navigator.of(context).pop(key),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    final sent = await ref.read(togetherActionsProvider.notifier).cheer(chosen);
    if (sent && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.cheerSent)));
    }
  }
}

/// The words of cheer [key].
String cheerText(AppLocalizations l10n, CheerKey key) => switch (key) {
  CheerKey.steady => l10n.cheerSteady,
  CheerKey.speaking => l10n.cheerSpeaking,
  CheerKey.together => l10n.cheerTogether,
};

/// Two arcs one after the other on a track; each a share of the goal.
class _Ring extends CustomPainter {
  new({
    required this.first,
    required this.second,
    required this.firstColor,
    required this.secondColor,
    required this.track,
  });

  final double first;
  final double second;
  final Color firstColor;
  final Color secondColor;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 10.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(width / 2);
    Paint stroke(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(arc, 0, 2 * pi, false, stroke(track));
    final a = first.clamp(0.0, 1.0) * 2 * pi;
    final b = second.clamp(0.0, 1.0 - first.clamp(0.0, 1.0)) * 2 * pi;
    const start = -pi / 2;
    if (a > 0) canvas.drawArc(arc, start, a, false, stroke(firstColor));
    if (b > 0) canvas.drawArc(arc, start + a, b, false, stroke(secondColor));
  }

  @override
  bool shouldRepaint(_Ring old) =>
      old.first != first ||
      old.second != second ||
      old.firstColor != firstColor ||
      old.secondColor != secondColor;
}
