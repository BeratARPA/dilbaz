import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';

/// The three rounds of 4/3/2 (A12, docs/03-activities.md): one topic told
/// again in less time each round (P16). The times grow with the level:
/// 90/60/45 s up to A1, 2/1.5/1 min at A2, 4/3/2 min from B1 on.
List<Duration> fluencyRounds(CefrLevel level) {
  if (level.isAtMost(CefrLevel.a1)) {
    return const [
      Duration(seconds: 90),
      Duration(seconds: 60),
      Duration(seconds: 45),
    ];
  }
  if (level == CefrLevel.a2) {
    return const [
      Duration(minutes: 2),
      Duration(seconds: 90),
      Duration(minutes: 1),
    ];
  }
  return const [
    Duration(minutes: 4),
    Duration(minutes: 3),
    Duration(minutes: 2),
  ];
}

/// A task the learner has spoken about, and when last (UTC).
typedef SpokenTopic = ({String key, DateTime lastSpoken});

/// The topics 4/3/2 may take, best first (A12 step 1; I-14: the learner
/// chooses): only tasks already spoken about, so that no new word is
/// needed. Topics not told in a 4/3/2 lately come first; within each
/// group the most recently spoken comes first, its words the freshest.
List<String> fluencyTopics({
  required Iterable<SpokenTopic> spoken,
  Set<String> toldLately = const {},
}) {
  final topics = [...spoken]
    ..sort((a, b) {
      final told =
          (toldLately.contains(a.key) ? 1 : 0) -
          (toldLately.contains(b.key) ? 1 : 0);
      if (told != 0) return told;
      final byTime = b.lastSpoken.compareTo(a.lastSpoken);
      return byTime != 0 ? byTime : a.key.compareTo(b.key);
    });
  return [for (final topic in topics) topic.key];
}
