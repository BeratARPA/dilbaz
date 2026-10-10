import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'gap_suggest_request.freezed.dart';

/// What the learner could not say, for `tutor/gap_suggest`
/// (docs/07-ai-tutor.md §4.3).
@freezed
abstract class GapSuggestRequest with _$GapSuggestRequest {
  const factory({
    required String l1,
    required String l2,
    required CefrLevel level,

    /// Notes in the learner's language (the level's scaffolds).
    required bool explainInL1,
    required String l1Text,
    required GapContext context,
    String? note,
  }) = _GapSuggestRequest;

  const new _();

  /// The route's body.
  Map<String, Object?> toJson() => {
    'ctx': {
      'l1': l1,
      'l2': l2,
      'level': level.code,
      'explain_in': explainInL1 ? 'l1' : 'l2',
    },
    'l1_text': l1Text,
    'context': context.code,
    'note': ?note,
  };
}
