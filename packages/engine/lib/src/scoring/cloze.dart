import 'package:dilbaz_engine/src/language/language_services.dart';
import 'package:dilbaz_engine/src/language/normalizer.dart';
import 'package:dilbaz_engine/src/scoring/answer_key.dart';

/// The gap of a cloze card and how an answer fills it (A04, docs/03).
///
/// The gap covers the reference's words that are forms of the target
/// lemmas, from the first to the last; punctuation around them stays
/// outside. Punctuation is what the pack's normalization drops (I-15). An
/// answer is checked as the whole sentence it makes, so the card's checks,
/// hints and LLM work on it as on any card (docs/03 §0.5).
final class Cloze {
  const new _({required this.before, required this.gap, required this.after});

  /// The cloze of [key] in [language]; null when the reference has no word
  /// of the target, or nothing but it.
  static Cloze? of(AnswerKey key, LanguageServices language) {
    final lemmas = key.targetLemmas;
    if (lemmas.isEmpty) return null;
    final words = [
      for (final word in key.reference.trim().split(Normalizer.space))
        if (word.isNotEmpty) word,
    ];
    bool target(String word) => language
        .tokenize(word)
        .any((token) => language.lemmasOf(token).any(lemmas.contains));
    final first = words.indexWhere(target);
    if (first < 0) return null;
    final last = words.lastIndexWhere(target);
    final span = words.sublist(first, last + 1).join(Normalizer.space);
    bool kept(String char) => language.tokenize(char).isNotEmpty;
    var start = 0;
    while (start < span.length && !kept(span[start])) {
      start++;
    }
    var end = span.length;
    while (end > start && !kept(span[end - 1])) {
      end--;
    }
    final prefix = words.take(first).join(Normalizer.space);
    final suffix = words.skip(last + 1).join(Normalizer.space);
    final cloze = Cloze._(
      before: [
        if (prefix.isNotEmpty) '$prefix${Normalizer.space}',
        span.substring(0, start),
      ].join(),
      gap: span.substring(start, end),
      after: [
        span.substring(end),
        if (suffix.isNotEmpty) '${Normalizer.space}$suffix',
      ].join(),
    );
    if (language.tokenize('${cloze.before} ${cloze.after}').isEmpty) {
      return null;
    }
    return cloze;
  }

  /// The sentence up to the gap, with the space before it.
  final String before;

  /// The words the gap stands for.
  final String gap;

  /// The sentence after the gap, from its punctuation on.
  final String after;

  /// The sentence [answer] makes in [language]: the answer itself when the
  /// learner said the whole sentence (it has the first and the last word
  /// around the gap), else the answer in the gap.
  String fill(String answer, LanguageServices language) {
    final said = answer.trim();
    final words = language.tokenize(said);
    final rest = language.tokenize('$before $after');
    final gap = language.tokenize(this.gap);
    if (words.length > gap.length &&
        words.contains(rest.first) &&
        words.contains(rest.last)) {
      return said;
    }
    return '$before$said$after';
  }
}
