import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/curriculum/item_kind.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'content_item.freezed.dart';

/// A learnable item from a language pack or a personal item.
///
/// The engine treats [key] as opaque (`{l2}.{kind}.{id}` for pack items,
/// `personal:<uuid>` for personal items; docs/11-language-packs.md §4).
@freezed
abstract class ContentItem with _$ContentItem {
  /// Creates an item.
  const factory({
    /// Permanent item key.
    required String key,

    /// Node kind.
    required ItemKind kind,

    /// CEFR level of the item.
    required CefrLevel level,

    /// Lemmas of all words in the item (coverage, carrier choice, transfer).
    @Default(<String>[]) List<String> lemmas,

    /// Keys of the items a sentence carries.
    @Default(<String>[]) List<String> targets,

    /// Closed-list grammar codes the item uses.
    @Default(<String>[]) List<String> grammarCodes,

    /// Surface text in the target language, when the kind has one.
    String? text,

    /// Frequency rank of the underlying lemma (word senses).
    int? rank,

    /// Removed from the pack; its cards are suspended, history is kept.
    @Default(false) bool deprecated,
  }) = _ContentItem;
}
