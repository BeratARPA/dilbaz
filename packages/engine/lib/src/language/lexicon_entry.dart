import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'lexicon_entry.freezed.dart';

/// One lemma of a target-language lexicon (`lexicon.jsonl`).
@freezed
abstract class LexiconEntry with _$LexiconEntry {
  /// Creates a lexicon entry.
  const factory({
    /// Dictionary form.
    required String lemma,

    /// Frequency rank, 1 = most frequent.
    required int rank,

    /// CEFR level from the pack's level sources.
    required CefrLevel level,

    /// Universal Dependencies part-of-speech tag.
    required String pos,
  }) = _LexiconEntry;
}
