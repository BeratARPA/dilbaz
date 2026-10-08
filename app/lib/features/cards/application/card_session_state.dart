import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'card_session_state.freezed.dart';

/// How the learner answers a card: aloud (A01) or typed (A02).
enum AnswerInput { speak, type }

/// What the latest answer of a card that goes on was.
enum AnswerFeedback {
  /// It missed: the hints so far, and another try.
  tryAgain,

  /// Correct, but without the card's target: the prompt is asked again
  /// (docs/03 §0.2).
  withoutTarget,

  /// Nothing usable was heard; it does not count.
  unheard,
}

/// One hint of the ladder (docs/03 §0.5): the LLM's words, or a template
/// the screen words from the ARB file.
@freezed
sealed class Hint with _$Hint {
  /// Written by the LLM, in the level's explanation language.
  const factory written(String text) = WrittenHint;

  /// H1: the kind of difference.
  const factory kind(HintKind kind) = KindHint;

  /// H2: where it is, told with one of the learner's own words.
  const factory place(HintPlace place) = PlaceHint;
}

/// The learner's latest answer, as the card shows it.
@freezed
abstract class LastAnswer with _$LastAnswer {
  const factory({
    required String text,

    /// Heard by speech recognition, not typed.
    required bool heard,

    /// Null while it waits for "did you mean …?" and once it ended the
    /// review.
    AnswerFeedback? feedback,

    /// Where the LLM found the errors in [text].
    @Default(<ErrorSpan>[]) List<ErrorSpan> spans,
  }) = _LastAnswer;
}

/// Where a card is.
@freezed
sealed class CardPhase with _$CardPhase {
  /// Waiting for an answer.
  const factory asking() = CardAsking;

  /// Recording the answer.
  const factory listening() = CardListening;

  /// Recognizing and checking the answer.
  const factory checking() = CardChecking;

  /// The LLM was not sure: "did you mean …?" (docs/03 §0.2).
  const factory confirming() = CardConfirming;

  /// The review is over: the correct sentence, to hear and say once
  /// (A01 step 7).
  const factory ended({
    required ReviewOutcome outcome,

    /// The card's sentence; its clip says it.
    required String sentence,

    /// The learner's answer corrected, when it is not the sentence.
    String? correction,

    /// Recalled, with a small error elsewhere in the sentence.
    @Default(false) bool almost,
  }) = CardEnded;
}

/// A card on screen (A01, A02).
@freezed
abstract class CardView with _$CardView {
  const factory({
    /// Its place in the session: "7 / 12".
    required int number,
    required int total,

    /// The prompt in the learner's language.
    required String prompt,
    required AnswerInput input,
    required CardPhase phase,

    /// Speaking is allowed (audio consent).
    required bool canSpeak,

    /// When the prompt needs a situation ("to a friend").
    String? contextNote,

    /// Hints opened so far, H1 first.
    @Default(<Hint>[]) List<Hint> hints,

    /// Another hint (up to H3) can be opened.
    @Default(false) bool canHint,

    /// The answer can be shown: only after a try (I-01).
    @Default(false) bool canReveal,

    /// The latest answer was heard and may be typed instead ("yanlış
    /// duyuldu", docs/03 §0.3).
    @Default(false) bool canRetype,
    LastAnswer? last,

    /// Why the latest answer was checked without the LLM.
    TutorFailure? offline,
    SpeechFailure? speechFailure,
    RecordFailure? recordFailure,

    /// The card's sentence has a clip.
    @Default(false) bool hasClip,
    @Default(false) bool playing,
  }) = _CardView;
}

/// A new item before its first card (A00).
@freezed
abstract class IntroductionView with _$IntroductionView {
  const factory({
    required int number,
    required int total,

    /// The item and its meaning.
    required String headword,
    required String meaning,

    /// The carrier sentence and its meaning.
    required String sentence,
    required String sentenceMeaning,

    /// How its card will be answered.
    required AnswerInput input,
    String? usageNote,

    /// How it differs from an easily confused item.
    String? contrastNote,
    @Default(false) bool hasClip,
    @Default(false) bool playing,
  }) = _IntroductionView;
}

/// Where the learner is in a card session.
@freezed
sealed class CardSessionState with _$CardSessionState {
  /// No course, profile or packs on the device yet.
  const factory unavailable() = CardSessionUnavailable;

  /// Nothing to review and nothing new for now.
  const factory empty() = CardSessionEmpty;

  /// The day's time is used up: "Bugünlük yeter" (docs/05 §6).
  const factory enough() = CardSessionEnough;

  const factory introduction(IntroductionView view) = CardSessionIntroduction;

  const factory card(CardView view) = CardSessionCard;

  /// The session is over: what was done in it.
  const factory done({required int reviewed, required int introduced}) =
      CardSessionDone;
}
