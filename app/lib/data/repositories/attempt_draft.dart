import 'package:freezed_annotation/freezed_annotation.dart';

part 'attempt_draft.freezed.dart';

/// One answer of a card review before it is stored (docs/03-activities.md
/// §0.4). A review's attempts are written together when it ends; the last
/// one carries the review's rating and the card's new memory.
@freezed
abstract class AttemptDraft with _$AttemptDraft {
  /// Creates a draft.
  const factory({
    /// The activity code (docs/03), such as `card.produce_speak`.
    required String activity,

    /// What was asked: `{prompt_l1, reference, carrier?}`.
    required Map<String, Object?> prompt,

    /// What came back: `{text, source, transcript?, asr?, asr_override?}`.
    required Map<String, Object?> response,

    /// When the answer came (UTC).
    required DateTime createdAtClient,
    String? verdict,
    bool? targetOk,
    @Default(<String>[]) List<String> errorTags,

    /// Hints opened before this answer, and the highest of them.
    @Default(0) int hintsUsed,
    @Default(0) int hintMaxLevel,

    /// From the prompt to the start of the answer.
    int? latencyMs,

    /// Length of the answer.
    int? durationMs,

    /// `{route, pending, provider?, model?, code?}` when the LLM was asked
    /// or should be later.
    Map<String, Object?>? llm,
  }) = _AttemptDraft;
}
