import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'speaking_annotate_request.freezed.dart';

/// A speaking task's transcript for `tutor/speaking_annotate`
/// (docs/07-ai-tutor.md §4.2).
@freezed
abstract class SpeakingAnnotateRequest with _$SpeakingAnnotateRequest {
  const factory({
    required String l1,
    required String l2,
    required CefrLevel level,

    /// Strengths and hints in the learner's language (the level's
    /// scaffolds).
    required bool explainInL1,

    /// The task as the learner read it, and what doing it means.
    required String prompt,
    required String goal,
    required List<TimedWord> words,
    @Default(<String>[]) List<String> canDoCodes,

    /// The monthly test (docs/07 §2).
    @Default(false) bool assessment,
  }) = _SpeakingAnnotateRequest;

  const new _();

  /// The route's body.
  Map<String, Object?> toJson() => {
    'ctx': {
      'l1': l1,
      'l2': l2,
      'level': level.code,
      'explain_in': explainInL1 ? 'l1' : 'l2',
    },
    'task': {'prompt_l1': prompt, 'goal': goal, 'can_do_codes': canDoCodes},
    'words': [
      for (final (i, word) in words.indexed)
        {
          'i': i,
          'w': word.text,
          'start_ms': word.startMs,
          'end_ms': word.endMs,
        },
    ],
    'assessment': assessment,
  };
}
