import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'card_content.freezed.dart';

/// What a card shows and checks, from the packs (docs/03-activities.md
/// A00–A02): the prompt, the answer key and the clips of its carrier, and
/// what the introduction of its item tells.
@freezed
abstract class CardContent with _$CardContent {
  /// Creates a card's content.
  const factory({
    /// The item the card practises: a word sense or a chunk.
    required String itemKey,
    required ItemKind kind,

    /// The carrier: a sentence with the item, or the chunk itself.
    required String carrierKey,

    /// The prompt in the learner's language: the carrier's meaning.
    required String prompt,

    /// What the reference and every correct answer are compared with.
    required AnswerKey answerKey,

    /// The carrier's words that carry the target (the LLM's `target_span`).
    required String targetSpan,

    /// The item itself, for the introduction (A00): its text and meaning.
    required String headword,
    required String meaning,

    /// Grammar codes of the carrier.
    @Default(<String>[]) List<String> grammarCodes,

    /// When the prompt needs a situation ("to a friend", "formal").
    String? contextNote,

    /// The reference as heard, and slower (for A0–A1), in the pack's
    /// `pack-audio` bucket.
    String? clip,
    String? slowClip,

    /// The item's usage note and the contrast note with an easily
    /// confused item, for the introduction.
    String? usageNote,
    String? contrastNote,
  }) = _CardContent;
}
