import 'package:freezed_annotation/freezed_annotation.dart';

part 'speech_annotation.freezed.dart';
part 'speech_annotation.g.dart';

/// What `speaking_annotate` marked in a transcript (docs/07-ai-tutor.md
/// §4.2), as `recordings.annotation` stores it. Word indices point into the
/// transcript's words; spans include both ends.
///
/// The annotation gives boundaries, errors and the task's outcome; every
/// number is computed from it and the word times by the engine
/// (`SpeechMetrics`), never by the model.
@freezed
abstract class SpeechAnnotation with _$SpeechAnnotation {
  /// Creates an annotation. Reading one that is off the contract throws a
  /// `CheckedFromJsonException`.
  // ignore: invalid_annotation_target
  @JsonSerializable(checked: true)
  const factory({
    required TaskOutcome taskOutcome,
    @Default(<AnnotatedClause>[]) List<AnnotatedClause> clauses,
    @Default(<SpeechError>[]) List<SpeechError> errors,
    @Default(<SpokenFiller>[]) List<SpokenFiller> fillers,

    /// Self-corrections and repetitions.
    @Default(<WordSpan>[]) List<WordSpan> repairs,

    /// Grammar points used, by the pack's closed codes (docs/04 §4.2).
    @Default(<StructureUse>[]) List<StructureUse> structuresUsed,

    /// What went well: at most two concrete things, in the explanation
    /// language.
    @Default(<String>[]) List<String> strengths,

    /// Corrections to choose from; the engine picks what is practised
    /// (`pickCorrections`).
    @Default(<SpeechCorrection>[]) List<SpeechCorrection> corrections,
  }) = _SpeechAnnotation;

  /// Reads a stored annotation.
  factory fromJson(Map<String, Object?> json) =>
      _$SpeechAnnotationFromJson(json);
}

/// Whether the task was done (docs/04 §5).
@JsonEnum(fieldRename: FieldRename.snake)
enum TaskOutcome {
  /// The task's goal was reached.
  done,

  /// Part of it.
  partial,

  /// Not reached.
  notDone,
}

/// A clause and the analysis of speech unit (AS-unit) it belongs to
/// (Foster, Tonkyn & Wigglesworth, 2000).
@freezed
abstract class AnnotatedClause with _$AnnotatedClause {
  /// Creates a clause.
  const factory({
    required int startI,
    required int endI,

    /// The AS-unit's number: clauses with the same number form one unit.
    required int asUnit,
    required bool errorFree,
  }) = _AnnotatedClause;

  /// Reads a stored clause.
  factory fromJson(Map<String, Object?> json) =>
      _$AnnotatedClauseFromJson(json);
}

/// An error, by the pair's closed tag list.
@freezed
abstract class SpeechError with _$SpeechError {
  /// Creates an error.
  const factory({
    required int startI,
    required int endI,
    required String tag,

    /// The words as they should be.
    required String correction,

    /// 1 small, 2 noticeable, 3 the meaning breaks.
    required int severity,
  }) = _SpeechError;

  /// Reads a stored error.
  factory fromJson(Map<String, Object?> json) => _$SpeechErrorFromJson(json);
}

/// Whose hesitation a filler is.
enum FillerKind {
  /// The target language's ("uh").
  l2,

  /// The learner's own language's.
  l1,
}

/// A hesitation word of the transcript.
@freezed
abstract class SpokenFiller with _$SpokenFiller {
  /// Creates a filler.
  const factory({required int i, required FillerKind kind}) = _SpokenFiller;

  /// Reads a stored filler.
  factory fromJson(Map<String, Object?> json) => _$SpokenFillerFromJson(json);
}

/// Words from [startI] to [endI].
@freezed
abstract class WordSpan with _$WordSpan {
  /// Creates a span.
  const factory({required int startI, required int endI}) = _WordSpan;

  /// Reads a stored span.
  factory fromJson(Map<String, Object?> json) => _$WordSpanFromJson(json);
}

/// A grammar point used in the transcript, and whether it was right.
@freezed
abstract class StructureUse with _$StructureUse {
  /// Creates a use.
  const factory({
    required String code,
    required int startI,
    required int endI,
    required bool correct,
  }) = _StructureUse;

  /// Reads a stored use.
  factory fromJson(Map<String, Object?> json) => _$StructureUseFromJson(json);
}

/// A sentence of the learner to correct, with its hint ladder (I-02): the
/// corrected sentence is the last step.
@freezed
abstract class SpeechCorrection with _$SpeechCorrection {
  /// Creates a correction.
  const factory({
    /// The learner's sentence as they said it.
    required String original,
    required String corrected,
    required String tag,

    /// As the error's severity.
    required int severity,
    required CorrectionLadder ladder,

    /// What [corrected] means in the learner's language: the prompt of its
    /// card (docs/03 A11 step 5).
    @JsonKey(name: 'meaning_l1') String? meaningL1,
  }) = _SpeechCorrection;

  /// Reads a stored correction.
  factory fromJson(Map<String, Object?> json) =>
      _$SpeechCorrectionFromJson(json);
}

/// H1 kind, H2 place, H3 rule; none of them gives the correction away.
@freezed
abstract class CorrectionLadder with _$CorrectionLadder {
  /// Creates a ladder.
  const factory({required String h1, required String h2, required String h3}) =
      _CorrectionLadder;

  /// Reads a stored ladder.
  factory fromJson(Map<String, Object?> json) =>
      _$CorrectionLadderFromJson(json);
}
