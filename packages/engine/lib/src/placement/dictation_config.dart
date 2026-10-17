import 'package:freezed_annotation/freezed_annotation.dart';

part 'dictation_config.freezed.dart';

/// Settings of dictation scoring (docs/06-assessment.md §2, part 3).
@freezed
abstract class DictationConfig with _$DictationConfig {
  /// Creates settings; the defaults are the documented values.
  const factory({
    /// Words from this many letters on may be misspelt by one edit.
    @Default(4) int slipLength,

    /// Words from this many letters on may be misspelt by two edits.
    @Default(8) int longSlipLength,

    /// A level is reached up to this word error rate
    /// (docs/04-learner-model.md §7).
    @Default(0.15) double maxErrorRate,

    /// A lemma this frequent or more is a function word: missing it or
    /// writing another word in its place is a weak form not heard (A05,
    /// `perc.weak_forms`). Ranks come from the pack's lexicon.
    @Default(60) int weakRank,

    /// A dictation card is Hard up to this word error rate, Again above
    /// it; without an error it is Good.
    @Default(0.25) double hardErrorRate,
  }) = _DictationConfig;
}
