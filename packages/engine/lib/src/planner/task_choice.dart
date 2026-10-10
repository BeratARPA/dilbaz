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

/// A task of the packs as the monthly test sees it.
typedef TestTask = ({String key, CefrLevel level, String? anchor});

/// The tasks of a monthly speaking test (docs/06 §3.1): the anchors in
/// their order, the same every month, then [count] tasks of the learner's
/// level taken in turn, so that each month brings others. Below A1 the A1
/// tasks are taken; a level without tasks takes the nearest one below.
/// [month] counts months (year × 12 + month).
List<String> monthlyTasks({
  required Iterable<TestTask> tasks,
  required CefrLevel level,
  required int month,
  int count = 2,
}) {
  final anchors = [
    for (final task in tasks)
      if (task.anchor != null) task,
  ]..sort((a, b) => _anchorOrder(a.anchor!).compareTo(_anchorOrder(b.anchor!)));
  final practice = [
    for (final task in tasks)
      if (task.anchor == null) task,
  ];
  var reach = level.isAtMost(CefrLevel.a1) ? CefrLevel.a1 : level;
  var pool = <TestTask>[];
  while (true) {
    final at = reach;
    pool = [
      for (final task in practice)
        if (task.level == at) task,
    ]..sort((a, b) => a.key.compareTo(b.key));
    if (pool.isNotEmpty || reach == CefrLevel.a0) break;
    reach = CefrLevel.values[reach.index - 1];
  }
  final taken = pool.isEmpty ? 0 : (count < pool.length ? count : pool.length);
  final start = pool.isEmpty ? 0 : (month * count) % pool.length;
  return [
    for (final task in anchors) task.key,
    for (var i = 0; i < taken; i++) pool[(start + i) % pool.length].key,
  ];
}

/// ANC-2 before ANC-10: the number after the dash.
int _anchorOrder(String anchor) =>
    int.tryParse(anchor.substring(anchor.lastIndexOf('-') + 1)) ?? 0;
