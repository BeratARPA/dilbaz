import 'package:dilbaz_engine/src/language/normalization_rules.dart';

/// Applies one language's normalization rules, so that answers, references
/// and variants compare word for word (docs/03-activities.md §0.5).
///
/// The steps and their order are those documented in `normalization.yaml`
/// and shared with the content tools (`dilbaz_content.normalize`); the rules
/// themselves are pack data (I-15). Words are joined by [separator], a
/// single character; whitespace also separates words.
final class Normalizer {
  /// A normalizer for [rules].
  new(this.rules, {this.separator = space})
    : _apostrophes = rules.apostrophes.toSet(),
      _punctuation = rules.punctuation.runes.toSet() {
    _check(rules, separator);
  }

  /// The `space` word separator (`script.word_separator`).
  static const space = ' ';

  /// The canonical apostrophe: step 2 maps the others to it, step 5 drops it.
  static const _apostrophe = "'";

  /// The rules applied.
  final NormalizationRules rules;

  /// What separates words in normalized text.
  final String separator;

  final Set<String> _apostrophes;
  final Set<int> _punctuation;

  /// The normalized form of [text].
  String normalize(String text) {
    final cleaned = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      if (_apostrophes.contains(char)) {
        cleaned.write(_apostrophe);
      } else if (_punctuation.contains(rune)) {
        cleaned.write(separator);
      } else {
        cleaned.write(char);
      }
    }
    final expanded = _join(words(cleaned.toString()).map(_expand));
    final spelled = _join(words(expanded).map(_spell));
    return _join(words(_phrase(spelled)).map(_number));
  }

  /// Words of [text], split at the separator and at whitespace.
  List<String> words(String text) {
    final found = <String>[];
    final word = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (char != separator && char.trim().isNotEmpty) {
        word.write(char);
      } else if (word.isNotEmpty) {
        found.add(word.toString());
        word.clear();
      }
    }
    if (word.isNotEmpty) found.add(word.toString());
    return found;
  }

  String _join(Iterable<String> words) => words.join(separator);

  String _expand(String word) {
    final sign = String.fromCharCode(word.runes.first);
    final amount = word.substring(sign.length);
    final names = rules.currency[sign];
    if (names != null && _isDigits(amount)) {
      return '$amount$separator${amount == '1' ? names.first : names.last}';
    }
    final whole = rules.words[word];
    if (whole != null) return whole;
    for (final MapEntry(key: ending, value: replacement)
        in rules.endings.entries) {
      if (word.length > ending.length && word.endsWith(ending)) {
        return '${word.substring(0, word.length - ending.length)}'
            '$replacement';
      }
    }
    return word;
  }

  String _spell(String word) => (rules.spellings[word] ?? word)
      .replaceAll(_apostrophe, '')
      .replaceAll('-', separator);

  String _phrase(String text) {
    var padded = '$separator$text$separator';
    for (final MapEntry(key: phrase, value: replacement)
        in rules.phrases.entries) {
      padded = padded.replaceAll(
        '$separator$phrase$separator',
        '$separator$replacement$separator',
      );
    }
    return padded;
  }

  String _number(String word) {
    if (rules.numbers == null || !_isDigits(word)) return word;
    final value = int.parse(word);
    return value < 1000 ? _say(value) : word;
  }

  String _say(int value) {
    final numbers = rules.numbers!;
    if (value < 20) return numbers.units[value];
    if (value < 100) {
      final tens = numbers.tens[value ~/ 10] ?? '';
      return value % 10 == 0
          ? tens
          : '$tens$separator${numbers.units[value % 10]}';
    }
    final head = '${numbers.units[value ~/ 100]}$separator${numbers.hundred}';
    return value % 100 == 0 ? head : '$head$separator${_say(value % 100)}';
  }

  /// ASCII digits only, like the content tools.
  static bool _isDigits(String text) =>
      text.isNotEmpty && text.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

  static void _check(NormalizationRules rules, String separator) {
    if (separator.runes.length != 1) {
      throw ArgumentError.value(separator, 'separator', 'one_character');
    }
    final numbers = rules.numbers;
    if (numbers != null &&
        (numbers.units.length != 20 || numbers.tens.length != 10)) {
      throw ArgumentError.value(numbers, 'numbers', 'needs_20_units_10_tens');
    }
    for (final MapEntry(:key, :value) in rules.currency.entries) {
      if (key.runes.length != 1 || value.length != 2) {
        throw ArgumentError.value(key, 'currency', 'needs_sign_and_two_words');
      }
    }
  }
}
