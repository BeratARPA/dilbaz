import 'package:dilbaz_engine/src/fsrs/review_rating.dart';
import 'package:dilbaz_engine/src/language/edit_distance.dart';
import 'package:dilbaz_engine/src/language/language_services.dart';
import 'package:dilbaz_engine/src/language/word_alignment.dart';
import 'package:dilbaz_engine/src/language/word_diff.dart';
import 'package:dilbaz_engine/src/placement/dictation_config.dart';

/// What became of one word of a dictation sentence (A05 steps 3–4).
enum DictationMark {
  /// Written as said.
  heard,

  /// Misspelt but heard: no word of the language, a letter or two off.
  slip,

  /// The same word without its ending, or with another: `work` for
  /// `works` (`perc.endings`).
  ending,

  /// A function word missed or heard as another (`perc.weak_forms`).
  weakForm,

  /// Missed.
  missed,

  /// Another word, or one out of its place.
  changed,
}

/// A sentence written down from hearing, word by word against the
/// sentence (A05): the marks, the words too many, and the errors that
/// count. Spelling is not hearing: a slip is no error. Deterministic; no
/// LLM (docs/03 A05).
final class DictationCheck {
  const new _({required this.words, required this.marks, required this.extra});

  /// Checks what was [typed] against the [expected] sentence. [rankOf]
  /// gives a lemma's frequency rank, so that function words are known
  /// without a list of them (I-15).
  factory of({
    required String expected,
    required String typed,
    required LanguageServices language,
    int? Function(String lemma)? rankOf,
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
    bool frequent(String word) => language
        .lemmasOf(word)
        .any((lemma) => (rankOf?.call(lemma) ?? 1 << 30) <= config.weakRank);
    final marks = List.filled(words.length, DictationMark.heard);
    final extra = <String>[];
    for (final diff in alignment.diffs) {
      switch (diff.kind) {
        case WordDiffKind.extra:
          extra.addAll([for (final i in diff.actual) written[i]]);
        case WordDiffKind.form:
          final wanted = words[diff.expected.single];
          final heard = written[diff.actual.single];
          marks[diff.expected.single] =
              wanted.startsWith(heard) || heard.startsWith(wanted)
              ? DictationMark.ending
              : DictationMark.changed;
        case WordDiffKind.missing:
          for (final i in diff.expected) {
            marks[i] = frequent(words[i])
                ? DictationMark.weakForm
                : DictationMark.missed;
          }
        case WordDiffKind.other:
          final i = diff.expected.single;
          final heard = written[diff.actual.single];
          marks[i] = !language.knows(heard) && _isSlip(words[i], heard, config)
              ? DictationMark.slip
              : frequent(words[i])
              ? DictationMark.weakForm
              : DictationMark.changed;
        case WordDiffKind.order:
          for (final i in diff.expected) {
            marks[i] = DictationMark.changed;
          }
      }
    }
    return DictationCheck._(
      words: List.unmodifiable(words),
      marks: List.unmodifiable(marks),
      extra: List.unmodifiable(extra),
    );
  }

  /// The words of the sentence.
  final List<String> words;

  /// What became of each of [words].
  final List<DictationMark> marks;

  /// Words written that the sentence does not have.
  final List<String> extra;

  /// Words missed, changed or added; slips are not errors.
  int get errors =>
      marks
          .where((m) => m != DictationMark.heard && m != DictationMark.slip)
          .length +
      extra.length;

  /// Errors per word of the sentence, at most 1.
  double get errorRate =>
      words.isEmpty ? 0 : (errors / words.length).clamp(0, 1).toDouble();

  /// The card's rating (A05, FSRS): Good without an error, Hard up to
  /// [DictationConfig.hardErrorRate], else Again.
  ReviewRating rating({DictationConfig config = const DictationConfig()}) {
    if (errors == 0) return ReviewRating.good;
    return errorRate <= config.hardErrorRate
        ? ReviewRating.hard
        : ReviewRating.again;
  }

  static bool _isSlip(String wanted, String written, DictationConfig config) {
    final length = wanted.runes.length;
    if (length < config.slipLength) return false;
    return editDistance(wanted, written) <=
        (length >= config.longSlipLength ? 2 : 1);
  }
}
