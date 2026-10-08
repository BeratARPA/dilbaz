import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'speaking_task.freezed.dart';

/// A speaking task of the packs (A11, A23; docs/02-curriculum.md §7): what
/// to talk about in the target language's terms, and what the learner
/// reads.
@freezed
abstract class SpeakingTask with _$SpeakingTask {
  const factory({
    required String key,

    /// The lowest level the task suits.
    required CefrLevel level,

    /// What doing the task means; the tutor judges the outcome against it.
    required String goal,
    required String title,

    /// The task as the learner reads it.
    required String prompt,

    /// ANC-1…3: a fixed task of the monthly test, not offered as practice.
    String? anchor,
    @Default(<String>[]) List<String> canDo,

    /// Sentence starters shown with the task at A levels, and what they
    /// mean; "..." is the learner's part.
    @Default(<String>[]) List<String> phrases,
    @Default(<String>[]) List<String> phraseMeanings,
  }) = _SpeakingTask;
}
