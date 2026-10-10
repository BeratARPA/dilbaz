import 'package:freezed_annotation/freezed_annotation.dart';

part 'number_words.freezed.dart';
part 'number_words.g.dart';

/// Words for the numbers 0–999 (`normalization.yaml` → `numbers`).
@freezed
abstract class NumberWords with _$NumberWords {
  /// Creates number words.
  const factory({
    /// Words for 0–19.
    required List<String> units,

    /// Words for the tens, by index (20 at 2); null where [units] cover it.
    required List<String?> tens,

    /// Word for a hundred.
    required String hundred,
  }) = _NumberWords;

  /// Reads number words from their pack JSON.
  factory fromJson(Map<String, Object?> json) => _$NumberWordsFromJson(json);
}
