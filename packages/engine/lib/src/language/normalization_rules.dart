import 'package:dilbaz_engine/src/language/number_words.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'normalization_rules.freezed.dart';
part 'normalization_rules.g.dart';

/// A target language's answer normalization rules: the pack's
/// `normalization.yaml`, stored as JSON in `pack_meta.normalization`
/// (docs/11-language-packs.md §5.1 and §6).
///
/// The order of [endings] and [phrases] matters; JSON keeps it.
@freezed
abstract class NormalizationRules with _$NormalizationRules {
  /// Creates rules.
  const factory({
    /// Version of the rules.
    required int version,

    /// Characters that stand for the apostrophe.
    @Default(<String>[]) List<String> apostrophes,

    /// Characters that separate words like a space.
    @Default('') String punctuation,

    /// Whole-word replacements.
    @Default(<String, String>{}) Map<String, String> words,

    /// Word endings and what replaces them, first match wins.
    @Default(<String, String>{}) Map<String, String> endings,

    /// Currency sign → its word for one and for more.
    @Default(<String, List<String>>{}) Map<String, List<String>> currency,

    /// Spelling variants → the spelling answers are compared in.
    @Default(<String, String>{}) Map<String, String> spellings,

    /// Whole-word phrases and their replacements, in order.
    @Default(<String, String>{}) Map<String, String> phrases,

    /// Words for numbers; digits stay digits without them.
    NumberWords? numbers,

    /// Examples every implementation must pass: `[text, normalized]`.
    @Default(<List<String>>[]) List<List<String>> tests,
  }) = _NormalizationRules;

  /// Reads rules from their pack JSON.
  factory fromJson(Map<String, Object?> json) =>
      _$NormalizationRulesFromJson(json);
}
