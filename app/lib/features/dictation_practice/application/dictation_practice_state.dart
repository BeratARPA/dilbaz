import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'dictation_practice_state.freezed.dart';

/// What one sentence came to: its words and their marks, what was written
/// and the words too many (A05 steps 3–4).
typedef DictationResult = ({
  List<String> words,
  List<DictationMark> marks,
  List<String> extra,
  String typed,
  int errors,
});

/// Where a dictation is (A05, docs/03).
@freezed
sealed class DictationPracticeState with _$DictationPracticeState {
  /// No course, profile or packs on the device yet.
  const factory unavailable() = DictationUnavailable;

  /// No sentence the learner can understand well enough yet (I-06).
  const factory nothingToHear() = DictationNothingToHear;

  /// Sentence [number] of [total]: listen, then write what was heard.
  const factory listening({
    required int number,
    required int total,

    /// The second try, after listening slowly (A05 step 5).
    required bool slow,
    @Default(false) bool playing,

    /// The clip was played at least once.
    @Default(false) bool heard,

    /// Why the clip could not be played.
    PackFailure? failure,
  }) = DictationListening;

  /// The sentence checked: what was heard right and what was not.
  const factory checked({
    required int number,
    required int total,
    required DictationResult result,

    /// A slower listen and a second try are offered (A05 step 5).
    required bool canTryAgain,
  }) = DictationChecked;

  /// Every sentence written: how many, and the errors of each kind.
  const factory done({
    required int sentences,
    required int heardRight,
    required Map<DictationMark, int> misses,
  }) = DictationDone;
}
