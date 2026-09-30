import 'package:freezed_annotation/freezed_annotation.dart';

part 'hint_place.freezed.dart';

/// Where a difference sits relative to the learner's own word.
enum HintRelation {
  /// Before the word.
  before,

  /// After the word.
  after,

  /// At the word itself.
  at,
}

/// H2 of a templated hint ladder: where the difference is, told only with
/// the learner's own words, so it never gives the answer away (I-02).
@freezed
abstract class HintPlace with _$HintPlace {
  /// Creates a place.
  const factory({
    /// Where the difference is relative to [word].
    required HintRelation relation,

    /// A word of the answer, normalized.
    required String word,

    /// Index of [word] among the answer's normalized words.
    required int index,
  }) = _HintPlace;
}
