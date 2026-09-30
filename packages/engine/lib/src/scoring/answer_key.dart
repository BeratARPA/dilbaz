import 'package:freezed_annotation/freezed_annotation.dart';

part 'answer_key.freezed.dart';

/// What an answer to one card is compared with (docs/03-activities.md
/// §0.5): the reference with the pack's variants and alternatives for it,
/// plus the learner's personal ones.
///
/// The packs list these per sentence. A sentence can carry several items,
/// so the checker decides per card whether a listed answer says the target.
@freezed
abstract class AnswerKey with _$AnswerKey {
  /// Creates an answer key.
  const factory({
    /// The reference answer: a carrier sentence or a chunk.
    required String reference,

    /// Lemmas of the card's target item; the target part is where they
    /// occur. With none, the whole answer is the target.
    required Set<String> targetLemmas,

    /// Other correct answers, listed as using the reference's targets.
    @Default(<String>[]) List<String> variants,

    /// Other correct answers, listed as lacking one of them; a correct
    /// answer without the card's target is asked again (§0.2).
    @Default(<String>[]) List<String> alternatives,

    /// Grammar code whose rule note is the card's H3: the target's own code
    /// on a grammar card. Null on word and chunk cards, where the notes of
    /// the sentence's grammar would not be about the miss.
    String? ruleCode,

    /// Grammar codes of the listed answers, by answer (the pair pack's
    /// `variants.grammar`). On a grammar card an answer says the target
    /// when it uses [ruleCode]'s structure.
    @Default(<String, List<String>>{}) Map<String, List<String>> answerGrammar,
  }) = _AnswerKey;
}
