import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/planner/seeded_random.dart';

/// A speaking task the learner may do: its key and the lowest level it
/// suits.
typedef TaskCandidate = ({String key, CefrLevel level});

/// The speaking tasks to offer, best first (A11; I-14: the learner
/// chooses).
///
/// A task suits a learner at or above its level; below A1 the A1 tasks
/// are offered with their scaffolds. Tasks of the learner's own level come
/// first, then lower ones, nearest first. A task done lately goes last,
/// so practice moves on. The order within a level is drawn from [seed]:
/// the same all day.
List<String> suggestTasks({
  required Iterable<TaskCandidate> tasks,
  required CefrLevel level,
  required int seed,
  Set<String> doneLately = const {},
}) {
  final reach = level.isAtMost(CefrLevel.a1) ? CefrLevel.a1 : level;
  final random = SeededRandom(seed);
  final suited = [
    for (final task in tasks)
      if (task.level.isAtMost(reach)) task,
  ]..sort((a, b) => a.key.compareTo(b.key));
  final drawn = random.shuffled(suited);
  int rank(TaskCandidate task) =>
      (doneLately.contains(task.key) ? 100 : 0) +
      (reach.scale - task.level.scale);
  final ordered = [...drawn.indexed]
    ..sort((a, b) {
      final byRank = rank(a.$2) - rank(b.$2);
      return byRank != 0 ? byRank : a.$1 - b.$1;
    });
  return [for (final (_, task) in ordered) task.key];
}
