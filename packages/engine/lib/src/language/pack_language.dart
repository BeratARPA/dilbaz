import 'package:dilbaz_engine/src/language/language_services.dart';
import 'package:dilbaz_engine/src/language/normalization_rules.dart';
import 'package:dilbaz_engine/src/language/normalizer.dart';

/// [LanguageServices] of a target pack: its normalization rules, word
/// separator (`script.word_separator`) and forms table (`content_forms`).
final class PackLanguage implements LanguageServices {
  /// Services for a pack's [rules] and `forms` (form → lemmas, lowercase).
  new({
    required NormalizationRules rules,
    required this._forms,
    String separator = Normalizer.space,
  }) : _normalizer = Normalizer(rules, separator: separator);

  final Normalizer _normalizer;
  final Map<String, Set<String>> _forms;

  @override
  String normalize(String text) => _normalizer.normalize(text);

  @override
  List<String> tokenize(String text) =>
      _normalizer.words(_normalizer.normalize(text));

  @override
  Set<String> lemmasOf(String token) => _forms[token] ?? {token};
}
