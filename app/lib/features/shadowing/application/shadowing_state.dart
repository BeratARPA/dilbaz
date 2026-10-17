import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'shadowing_state.freezed.dart';

/// A pronunciation problem as the learner sees it: the word, how it
/// sounded and what the problem is, in the learner's language.
typedef ShownIssue = ({String word, String heard, String tag, String about});

/// How the recording was heard (ADR-0011).
enum PronJudgement {
  /// Gemini listened; the problems shown are the ones it was sure of.
  heard,

  /// The recording could not be judged: noise, cut off, or another text.
  uncertain,

  /// Nobody listened: no consent, no quota or no connection. The words
  /// recognized and the learner's own ear remain.
  notHeard,
}

/// Where a shadowing is (A07, docs/03).
@freezed
sealed class ShadowingState with _$ShadowingState {
  /// No course, profile or packs on the device yet.
  const factory unavailable() = ShadowingUnavailable;

  /// The learner has not agreed to audio recordings (I-18).
  const factory needsConsent() = ShadowingNeedsConsent;

  /// No sentence the learner can follow yet (I-06).
  const factory nothingToSay() = ShadowingNothingToSay;

  /// Sentence [number] of [total]: listen, then say it the same way.
  const factory sentence({
    required int number,
    required int total,
    required String text,

    /// The second try (A07 step 5).
    required bool again,
    @Default(false) bool playing,

    /// The clip was played at least once.
    @Default(false) bool heard,
    @Default(false) bool recording,

    /// Why the clip could not be played.
    PackFailure? audioFailure,

    /// Why the last recording could not be used.
    SpeakingFailure? failure,
  }) = ShadowingSentence;

  /// The recording is being recognized and heard.
  const factory checking() = ShadowingChecking;

  /// What came of a try.
  const factory result({
    required int number,
    required int total,

    /// The sentence's words and how speech recognition heard each; null
    /// when it could not be recognized.
    required List<String> words,
    required List<DictationMark>? marks,

    /// At most two problems (`pickPronIssues`).
    required List<ShownIssue> issues,
    required PronJudgement judgement,

    /// A second try is offered (A07 step 5).
    required bool canTryAgain,

    /// The learner's own recording can be played next to the model.
    required bool canHearSelf,
    @Default(false) bool playing,
  }) = ShadowingResult;

  /// Every sentence said: how many, and the problems shown by kind.
  const factory done({
    required int sentences,
    required Map<String, int> shown,
    required Map<String, String> about,
  }) = ShadowingDone;
}
