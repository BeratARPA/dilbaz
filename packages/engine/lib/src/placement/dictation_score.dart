import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/language/edit_distance.dart';
import 'package:dilbaz_engine/src/language/language_services.dart';
import 'package:dilbaz_engine/src/language/word_alignment.dart';
import 'package:dilbaz_engine/src/language/word_diff.dart';
import 'package:dilbaz_engine/src/model/level_estimate.dart';
import 'package:dilbaz_engine/src/placement/dictation_config.dart';
import 'package:dilbaz_engine/src/placement/level_ladder.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'dictation_score.freezed.dart';

/// How well a sentence that was heard has been written down
/// (docs/03-activities.md A05, docs/06-assessment.md §2 part 3).
///
/// Dictation measures hearing, not spelling: a written word that is no
/// word of the language but within a letter or two of the expected one is
/// a spelling slip and no error. A real word in the wrong place is one: it
/// is what the learner heard.
@freezed
abstract class DictationScore with _$DictationScore {
  /// Creates a score; [DictationScore.of] computes one.
  const factory({
    /// Words of the sentence.
    required int words,

    /// Words missed, added, changed or out of order.
    required int errors,

    /// Misspelt words that were heard right.
    required int slips,
  }) = _DictationScore;

  /// Scores what was [typed] against the [expected] sentence.
  factory of({
    required String expected,
    required String typed,
    required LanguageServices language,
    DictationConfig config = const DictationConfig(),
  }) {
    final words = language.tokenize(expected);
    final written = language.tokenize(typed);
    final alignment = WordAlignment.of(
      words,
      written,
      sameLemma: (a, b) =>
          language.lemmasOf(a).any(language.lemmasOf(b).contains),
    );
    var slips = 0;
    for (final diff in alignment.diffs) {
      if (diff.kind != WordDiffKind.other) continue;
      final heard = written[diff.actual.single];
      final wanted = words[diff.expected.single];
      if (!language.knows(heard) && _isSlip(wanted, heard, config)) slips++;
    }
    return DictationScore(
      words: words.length,
      errors: alignment.diffs.length - slips,
      slips: slips,
    );
  }

  const new _();

  /// Errors per word of the sentence, at most 1.
  double get errorRate =>
      words == 0 ? 0 : (errors / words).clamp(0, 1).toDouble();

  static bool _isSlip(String wanted, String written, DictationConfig config) {
    final length = wanted.runes.length;
    if (length < config.slipLength) return false;
    return editDistance(wanted, written) <=
        (length >= config.longSlipLength ? 2 : 1);
  }

  /// The listening estimate from sentences of rising levels: a level is
  /// reached when the pooled error rate of its sentences is at most
  /// [DictationConfig.maxErrorRate].
  static LevelEstimate estimate(
    Iterable<(CefrLevel, DictationScore)> scores, {
    DictationConfig config = const DictationConfig(),
    String? source,
  }) {
    final words = <CefrLevel, int>{};
    final errors = <CefrLevel, int>{};
    for (final (level, score) in scores) {
      words[level] = (words[level] ?? 0) + score.words;
      errors[level] = (errors[level] ?? 0) + score.errors;
    }
    final tested = [
      for (final level in CefrLevel.values)
        if ((words[level] ?? 0) > 0) level,
    ];
    if (tested.isEmpty) throw ArgumentError.value(scores, 'scores', 'empty');
    return LevelLadder.estimate(
      {
        for (final level in tested)
          level: errors[level]! / words[level]! <= config.maxErrorRate,
      },
      tested: tested,
      source: source,
    );
  }
}
