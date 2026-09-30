import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/model/level_estimate.dart';

/// The recognition vocabulary of one level: X_Lex scores from `from` up to
/// but not including `to`.
typedef VocabRange = ({CefrLevel level, int from, int to});

/// Recognition vocabulary sizes of the levels (docs/02-curriculum.md §2).
///
/// The sizes come from studies of learners of one target language, so they
/// are pack data (`placement.vocab_levels` in the manifest), not engine
/// constants (I-15).
final class VocabLevels {
  /// Levels with their [ranges], in any order.
  new(Iterable<VocabRange> ranges)
    : ranges = [...ranges]..sort((a, b) => a.from.compareTo(b.from));

  /// Reads `placement.vocab_levels`: a list of `{level, from, to}`.
  factory fromJson(List<Object?> json) => VocabLevels([
    for (final entry in json.cast<Map<String, Object?>>())
      (
        level: CefrLevel.values.firstWhere((l) => l.code == entry[_level]),
        from: entry[_from]! as int,
        to: entry[_to]! as int,
      ),
  ]);

  static const _level = 'level';
  static const _from = 'from';
  static const _to = 'to';

  /// The ranges, ascending.
  final List<VocabRange> ranges;

  /// The vocabulary level of an X_Lex [score]. A score between the ranges
  /// of two levels gives the range from the lower to the higher one.
  LevelEstimate estimate(int score, {String? source}) {
    var below = ranges.first.level;
    for (final (:level, :from, :to) in ranges) {
      if (score < from) {
        return LevelEstimate.between(below, level, source: source);
      }
      if (score < to) return LevelEstimate.at(level, source: source);
      below = level;
    }
    return LevelEstimate.at(below, source: source);
  }
}
