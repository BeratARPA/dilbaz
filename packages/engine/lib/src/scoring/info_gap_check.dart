import 'package:dilbaz_engine/src/speaking/speech_annotation.dart';

/// The answer key of an information gap task (A15, ADR-0012).
sealed class InfoGapKey {
  const new();
}

/// One role picks one option.
final class ChooseKey extends InfoGapKey {
  /// The key of a task in which role [chooser] must pick [option].
  const new({required this.chooser, required this.option});

  /// The role that picks: 'a' or 'b'.
  final String chooser;

  /// The id of the right option.
  final String option;
}

/// Each role marks its own lines that differ from the partner's.
final class DifferencesKey extends InfoGapKey {
  /// The key of a differences task: the i-th lines of [a] and [b] are the
  /// two sides of the same difference.
  const new({required this.a, required this.b});

  /// Role a's lines that differ, by index.
  final List<int> a;

  /// Role b's lines that differ, in the same order.
  final List<int> b;
}

/// How an information gap task went: the differences (or the one choice)
/// found, out of their total, and the marks that were no difference.
final class InfoGapCheck {
  const new _({required this.found, required this.total, required this.wrong});

  /// Checks the partners' [answers] against [key]: by role, a choice's
  /// option id, or the line indices a role marked.
  factory of(InfoGapKey key, Map<String, Object?> answers) {
    switch (key) {
      case ChooseKey(:final chooser, :final option):
        final chosen = answers[chooser];
        return InfoGapCheck._(
          found: chosen == option ? 1 : 0,
          total: 1,
          wrong: chosen is String && chosen != option ? 1 : 0,
        );
      case DifferencesKey(:final a, :final b):
        Set<int> marked(String role) => switch (answers[role]) {
          final List<Object?> lines => {...lines.whereType<int>()},
          _ => const {},
        };
        final byA = marked('a');
        final byB = marked('b');
        var found = 0;
        for (var i = 0; i < a.length && i < b.length; i++) {
          // A difference is found when either partner marked it.
          if (byA.contains(a[i]) || byB.contains(b[i])) found++;
        }
        return InfoGapCheck._(
          found: found,
          total: a.length,
          wrong:
              byA.difference(a.toSet()).length +
              byB.difference(b.toSet()).length,
        );
    }
  }

  /// Differences found, or 1 for the right choice.
  final int found;

  /// Differences in the task, or 1 for a choice.
  final int total;

  /// Lines marked that were no difference, or 1 for a wrong choice.
  final int wrong;

  /// Every difference found (or the right choice), nothing marked wrong.
  bool get solved => found == total && wrong == 0;

  /// The task's outcome for its can-do evidence (docs/04 §5): done when
  /// solved, partial when something was found, else not done.
  TaskOutcome get outcome => solved
      ? TaskOutcome.done
      : found > 0
      ? TaskOutcome.partial
      : TaskOutcome.notDone;
}
