import 'package:freezed_annotation/freezed_annotation.dart';

part 'xlex_answer.freezed.dart';

/// One yes/no answer of an X_Lex vocabulary test
/// (docs/06-assessment.md §2).
@freezed
abstract class XlexAnswer with _$XlexAnswer {
  /// Creates an answer.
  const factory({
    /// The learner said they know the word.
    required bool known,

    /// Frequency band of a real word, 1 for the most frequent; null for a
    /// made-up word.
    int? band,
  }) = _XlexAnswer;
}
