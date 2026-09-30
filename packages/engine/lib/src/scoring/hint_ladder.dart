import 'package:dilbaz_engine/src/scoring/hint_kind.dart';
import 'package:dilbaz_engine/src/scoring/hint_place.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'hint_ladder.freezed.dart';

/// A templated hint ladder, built without the LLM (docs/03-activities.md
/// §0.5): the app words H1 and H2 from the ARB file and H3 from the pair
/// pack's rule notes. H1–H3 carry nothing of the correct answer (I-02).
@freezed
abstract class HintLadder with _$HintLadder {
  /// Creates a ladder.
  const factory({
    /// H1: the kind of difference.
    required HintKind kind,

    /// H4: the correct answer nearest to the learner's.
    required String answer,

    /// H2: where the difference is; null when it cannot be placed.
    HintPlace? place,

    /// H3: the grammar code whose rule note to show; null for none.
    String? ruleCode,
  }) = _HintLadder;
}
