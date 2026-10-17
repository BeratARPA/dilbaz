import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/planner/seeded_random.dart';

/// A sentence of the packs that dictation may take: its key, its lemmas
/// and its level.
typedef DictationCandidate = ({
  String key,
  List<String> lemmas,
  CefrLevel level,
});

/// The sentences of a dictation (A05), in order: the dictation cards due
/// first, then new sentences the learner can understand, [count] in all
/// and at most [newCount] new.
///
/// A new sentence needs a personal coverage of at least [minCoverage]
/// (I-06): dictation trains hearing what one knows, not guessing. It is at
/// the learner's level or below (A1 below A1); the learner's own level
/// comes first, the order within a level drawn from [seed].
List<String> pickDictations({
  required Iterable<DictationCandidate> candidates,
  required double Function(Iterable<String> lemmas) coverage,
  required CefrLevel level,
  required int seed,
  List<String> due = const [],
  Set<String> carded = const {},
  int count = 5,
  int newCount = 3,
  double minCoverage = 0.95,
}) {
  final known = {for (final candidate in candidates) candidate.key};
  final picked = [
    for (final key in due)
      if (known.contains(key)) key,
  ].take(count).toList();
  final reach = level.isAtMost(CefrLevel.a1) ? CefrLevel.a1 : level;
  final fresh = [
    for (final candidate in candidates)
      if (!carded.contains(candidate.key) &&
          !picked.contains(candidate.key) &&
          candidate.level.isAtMost(reach) &&
          coverage(candidate.lemmas) >= minCoverage)
        candidate,
  ]..sort((a, b) => a.key.compareTo(b.key));
  final drawn = SeededRandom(seed).shuffled(fresh);
  final ordered = [...drawn.indexed]
    ..sort((a, b) {
      final byLevel = b.$2.level.scale - a.$2.level.scale;
      return byLevel != 0 ? byLevel : a.$1 - b.$1;
    });
  final room = count - picked.length;
  return [
    ...picked,
    for (final (_, candidate) in ordered.take(
      room < newCount ? room : newCount,
    ))
      candidate.key,
  ];
}
