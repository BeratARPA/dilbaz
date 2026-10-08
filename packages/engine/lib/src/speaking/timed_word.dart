import 'package:freezed_annotation/freezed_annotation.dart';

part 'timed_word.freezed.dart';
part 'timed_word.g.dart';

/// One word of a transcript with its time in the recording
/// (docs/08-speech.md §3.3), as `recordings.asr.words` stores it. Speech
/// recognition keeps the learner's own forms and hesitation sounds.
@freezed
abstract class TimedWord with _$TimedWord {
  /// Creates a word.
  const factory({
    /// The word as recognized.
    @JsonKey(name: 'w') required String text,

    /// When it starts and ends, in milliseconds from the recording's start.
    required int startMs,
    required int endMs,

    /// The recognizer's confidence, 0–1, where it gives one.
    @JsonKey(name: 'conf') double? confidence,
  }) = _TimedWord;

  /// Reads a stored word.
  factory fromJson(Map<String, Object?> json) => _$TimedWordFromJson(json);
}
