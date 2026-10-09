import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/model/level_estimate.dart';
import 'package:dilbaz_engine/src/model/skill.dart';

/// Where a placement test puts the learner (docs/06-assessment.md §2).
final class PlacementOutcome {
  /// The outcome of the parts that were taken; a part left out is null.
  ///
  /// The curriculum starts at the lower of the vocabulary and grammar
  /// levels reached: new items build on both, so the weaker one leads. A
  /// test taken again may leave a part out; that part's estimate from an
  /// [earlier] test still counts. Listening has its own estimate and does
  /// not move the start. With neither part known the start stays at
  /// [fallback], the level the learner chose.
  factory of({
    required CefrLevel fallback,
    LevelEstimate? vocabulary,
    LevelEstimate? grammar,
    LevelEstimate? listening,
    Map<Skill, LevelEstimate> earlier = const {},
  }) {
    final reached = [
      ?(vocabulary ?? earlier[Skill.vocabulary])?.reached,
      ?(grammar ?? earlier[Skill.grammar])?.reached,
    ];
    return PlacementOutcome._(
      skills: {
        Skill.vocabulary: ?vocabulary,
        Skill.grammar: ?grammar,
        Skill.listening: ?listening,
      },
      start: reached.isEmpty
          ? fallback
          : reached.reduce((a, b) => a.isAtMost(b) ? a : b),
      measured: vocabulary != null || grammar != null,
    );
  }

  const new _({
    required this.skills,
    required this.start,
    required this.measured,
  });

  /// Key of the curriculum level in `courses.level_estimates`.
  static const overall = 'overall';

  /// Source code of estimates made by a placement test.
  static const source = 'placement';

  /// The estimate of each skill that was tested.
  final Map<Skill, LevelEstimate> skills;

  /// The level the curriculum starts at.
  final CefrLevel start;

  /// Whether the test measured vocabulary or grammar, so that [start] is
  /// new; otherwise the course keeps its level.
  final bool measured;

  /// The entries to write into `courses.level_estimates`: the tested
  /// skills, and the curriculum level when the test measured it.
  Map<String, Object?> toLevelEstimates() => {
    for (final MapEntry(key: skill, value: estimate) in skills.entries)
      skill.code: estimate.toJson(),
    if (measured) overall: LevelEstimate.at(start, source: source).toJson(),
  };
}
