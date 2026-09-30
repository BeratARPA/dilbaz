import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcript.freezed.dart';
part 'transcript.g.dart';

/// A word of a transcript with its time in the audio.
@freezed
abstract class TranscriptWord with _$TranscriptWord {
  const factory({
    required String w,
    @JsonKey(name: 'startMs') required int startMs,
    @JsonKey(name: 'endMs') required int endMs,
    double? conf,
  }) = _TranscriptWord;

  factory fromJson(Map<String, Object?> json) => _$TranscriptWordFromJson(json);
}

/// What the speech function heard, verbatim: fillers and the learner's own
/// forms are kept (docs/08-speech.md §2, §3.3).
@freezed
abstract class Transcript with _$Transcript {
  const factory({
    required String text,
    required String provider,
    required String model,
    @JsonKey(name: 'durationMs') required int durationMs,
    @Default(<TranscriptWord>[]) List<TranscriptWord> words,
  }) = _Transcript;

  factory fromJson(Map<String, Object?> json) => _$TranscriptFromJson(json);
}
