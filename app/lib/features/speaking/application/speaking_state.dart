import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/cards/application/card_session_state.dart'
    show Hint;
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'speaking_state.freezed.dart';

/// Why a recording could not be used.
enum SpeakingFailure {
  /// The system did not let the app use the microphone.
  permission,

  /// The microphone could not be opened, or this platform cannot record.
  microphone,

  /// Nothing was heard.
  silent,

  /// No connection: the recording waits for a later try.
  network,

  /// Speech recognition is busy, spent or not set up.
  speech,
}

/// What processing a recording is doing.
enum ProcessingStep {
  /// Writing down what was said.
  transcribing,

  /// The tutor marks the transcript.
  marking,
}

/// A task in the list to choose from.
typedef TaskChoice = ({String key, String title, CefrLevel level});

/// A recording whose feedback came later and waits (docs/08 §5.2): the
/// task's title and the day it was made, on the learner's clock.
typedef ReadyFeedback = ({String recordingId, String title, DateTime day});

/// A sentence starter of a task with what it means.
typedef TaskPhrase = ({String phrase, String meaning});

/// A task as its card shows it (docs/09 §5.6).
@freezed
abstract class TaskView with _$TaskView {
  const factory({
    required String key,
    required String title,
    required String prompt,

    /// Time to prepare, by the level's scaffolds; it can be cut short.
    required Duration preparation,

    /// Longest recording; it stops by itself then (docs/08 §4).
    required Duration limit,

    /// Sentence starters; at levels above A2 they open on request.
    @Default(<TaskPhrase>[]) List<TaskPhrase> phrases,
    @Default(true) bool phrasesOpen,
  }) = _TaskView;
}

/// Where the practice of one correction is (I-01, I-02).
enum CorrectionPhase {
  /// Waiting for an answer: first, or after a miss.
  asking,

  /// The microphone is on.
  listening,

  /// The answer is being written down.
  checking,

  /// Said right.
  recalled,

  /// The corrected sentence was opened, on request or after the last try.
  shown,
}

/// One correction to practise: the learner's sentence, the hints opened
/// so far and, once earned, the corrected sentence.
@freezed
abstract class CorrectionView with _$CorrectionView {
  const factory({
    required String original,
    required CorrectionPhase phase,
    @Default(<Hint>[]) List<Hint> hints,

    /// What the learner said or typed last.
    String? last,

    /// Null until it was said right or opened (I-01).
    String? corrected,
    @Default(false) bool canHint,
    @Default(false) bool canReveal,
  }) = _CorrectionView;
}

/// The feedback of a recording (docs/03 A11 step 4).
@freezed
abstract class FeedbackView with _$FeedbackView {
  const factory({
    required TaskView task,

    /// What was heard.
    required String transcript,
    required Duration spoken,
    required int words,
    @Default(<String>[]) List<String> strengths,

    /// Why the tutor's marks could not be had: the feedback is the
    /// measures alone, the marks come later.
    TutorFailure? waiting,
    @Default(<CorrectionView>[]) List<CorrectionView> corrections,

    /// The correction being practised.
    @Default(0) int current,

    /// Answers are typed (silent mode, no audio consent).
    @Default(false) bool typed,
  }) = _FeedbackView;
}

/// Where a speaking task is (A11, docs/09 §5.6).
@freezed
sealed class SpeakingState with _$SpeakingState {
  /// No course, profile or packs on the device yet.
  const factory unavailable() = SpeakingUnavailable;

  /// The learner has not agreed to audio recordings (docs/14, I-18).
  const factory needsConsent() = SpeakingNeedsConsent;

  /// The tasks to choose from; the planner suggests, the learner chooses
  /// (I-14).
  const factory choosing({
    required List<TaskChoice> suggested,
    required List<TaskChoice> others,
    @Default(<ReadyFeedback>[]) List<ReadyFeedback> ready,
  }) = SpeakingChoosing;

  /// The task card and the time to prepare.
  const factory preparing(TaskView task) = SpeakingPreparing;

  const factory recording(TaskView task) = SpeakingRecording;

  const factory processing(TaskView task, ProcessingStep step) =
      SpeakingProcessing;

  /// The recording could not be used; [canRetry] when it was kept.
  const factory failed(
    TaskView task,
    SpeakingFailure failure, {
    @Default(false) bool canRetry,
  }) = SpeakingFailed;

  const factory feedback(FeedbackView view) = SpeakingFeedback;

  /// Over: how many corrected sentences became cards.
  const factory done({required int cards}) = SpeakingDone;
}
