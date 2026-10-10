import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/speaking/speech_annotation.dart';

/// How far a can-do is shown (docs/04 §5).
enum CanDoStatus {
  /// No task of it yet.
  none,

  /// At least one task.
  attempted,

  /// At least one task done.
  shown,

  /// Done on different days with different prompts, lately.
  established,
}

/// One task outcome as evidence of a can-do.
typedef CanDoAttempt = ({
  String code,

  /// The local day of the task.
  DateTime day,

  /// The task, so that the same prompt twice counts once.
  String prompt,
  TaskOutcome outcome,

  /// Done with preparation time or phrases.
  bool scaffolded,
});

/// A can-do's status, and whether it is worth refreshing.
typedef CanDoEvidence = ({CanDoStatus status, bool refresh});

/// Rules of the can-do evidence (docs/04 §5).
abstract final class CanDoRules {
  /// Days the latest `done` of an established can-do may be old.
  static const establishedWithin = Duration(days: 60);

  /// An established can-do whose latest `done` is older is worth
  /// refreshing: an invitation, never a failure.
  static const refreshAfter = Duration(days: 120);

  /// `done` tasks on different days with different prompts.
  static const established = 2;

  /// From this level on, one `done` must be without scaffolds.
  static const CefrLevel unscaffoldedFrom = CefrLevel.b1;
}

/// The evidence of each can-do code of [attempts] at [now]; [levels] gives
/// each code's level.
Map<String, CanDoEvidence> canDoEvidence(
  Iterable<CanDoAttempt> attempts, {
  required DateTime now,
  Map<String, CefrLevel> levels = const {},
}) {
  final byCode = <String, List<CanDoAttempt>>{};
  for (final attempt in attempts) {
    (byCode[attempt.code] ??= []).add(attempt);
  }
  return {
    for (final MapEntry(:key, :value) in byCode.entries)
      key: _evidence(value, now, levels[key]),
  };
}

CanDoEvidence _evidence(
  List<CanDoAttempt> attempts,
  DateTime now,
  CefrLevel? level,
) {
  final done = [
    for (final attempt in attempts)
      if (attempt.outcome == TaskOutcome.done) attempt,
  ]..sort((a, b) => a.day.compareTo(b.day));
  if (done.isEmpty) return (status: CanDoStatus.attempted, refresh: false);
  final latest = done.last.day;
  final days = {for (final attempt in done) attempt.day};
  final prompts = {for (final attempt in done) attempt.prompt};
  final unscaffolded =
      level == null ||
      !CanDoRules.unscaffoldedFrom.isAtMost(level) ||
      done.any((attempt) => !attempt.scaffolded);
  final age = now.difference(latest);
  final established =
      days.length >= CanDoRules.established &&
      prompts.length >= CanDoRules.established &&
      unscaffolded;
  if (!established) return (status: CanDoStatus.shown, refresh: false);
  if (age > CanDoRules.establishedWithin) {
    return (status: CanDoStatus.shown, refresh: age > CanDoRules.refreshAfter);
  }
  return (status: CanDoStatus.established, refresh: false);
}
