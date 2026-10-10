import 'package:freezed_annotation/freezed_annotation.dart';

part 'gap_entry.freezed.dart';
part 'gap_entry.g.dart';

/// Where the learner could not say something (A19; `gap_entries.context`).
enum GapContext {
  liveClass('live_class'),
  daily('daily'),
  pair('pair'),
  speakingTask('speaking_task'),
  media('media');

  new(this.code);

  /// Code stored in `gap_entries.context` and sent to `gap_suggest`.
  final String code;
}

/// What became of a capture (`gap_entries.status`).
enum GapStatus {
  /// Waiting for the learner's decision, or for its suggestion.
  fresh('new'),

  /// Its sentence and phrase are personal items, on their way to cards.
  carded('carded'),
  dismissed('dismissed');

  new(this.code);

  final String code;
}

/// The phrase worth keeping, with its meaning in the learner's language.
@freezed
abstract class KeyChunk with _$KeyChunk {
  const factory({required String text, required String glossL1}) = _KeyChunk;

  factory fromJson(Map<String, Object?> json) => _$KeyChunkFromJson(json);
}

/// What `tutor/gap_suggest` said (docs/07-ai-tutor.md §4.3); stored as it
/// came in `gap_entries.suggestion`.
@freezed
abstract class GapSuggestion with _$GapSuggestion {
  // Anything off the contract fails as one exception, not a crash. freezed
  // moves the annotation to the generated class.
  // ignore: invalid_annotation_target
  @JsonSerializable(checked: true)
  const factory({
    /// How it is naturally said, and the same with the learner's words.
    required String l2Natural,
    required String l2Simple,
    required KeyChunk keyChunk,
    required String register,
    required String provider,
    required String model,

    /// Words of the simple version above the learner's level plus one.
    @Default(<String>[]) List<String> aboveLevel,
    @Default(false) bool simplified,
    String? notesL1,
  }) = _GapSuggestion;

  factory fromJson(Map<String, Object?> json) => _$GapSuggestionFromJson(json);
}

/// Something the learner could not say in the target language (A19).
@freezed
abstract class GapEntry with _$GapEntry {
  const factory({
    required String id,

    /// What they wanted to say, in their own language.
    required String l1Text,
    required GapContext context,
    required GapStatus status,
    required DateTime createdAt,
    String? note,

    /// Null until `gap_suggest` answers: the suggestion is pending.
    GapSuggestion? suggestion,
    @Default(<String>[]) List<String> personalItemIds,
  }) = _GapEntry;
}
