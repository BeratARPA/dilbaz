import 'package:freezed_annotation/freezed_annotation.dart';

part 'word_diff.freezed.dart';

/// Kind of one difference between an expected text and an answer.
enum WordDiffKind {
  /// An expected word is missing.
  missing,

  /// The answer has a word too many.
  extra,

  /// The expected word in another form (same lemma).
  form,

  /// Another word in place of the expected one.
  other,

  /// Expected words in another order: two neighbours swapped, or a word
  /// that turns up elsewhere.
  order,
}

/// One difference between an expected text and an answer, by word index.
@freezed
abstract class WordDiff with _$WordDiff {
  /// Creates a difference.
  const factory({
    /// What differs.
    required WordDiffKind kind,

    /// Indices of the expected words involved; none for an extra word.
    @Default(<int>[]) List<int> expected,

    /// Indices of the answer words involved; none for a missing word.
    @Default(<int>[]) List<int> actual,

    /// For an extra word: the index of the expected word it stands before.
    int? before,
  }) = _WordDiff;
}
