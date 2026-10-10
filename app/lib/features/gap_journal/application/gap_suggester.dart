import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/data/gap/gap_providers.dart';
import 'package:dilbaz_app/data/gap/gap_repository.dart';
import 'package:dilbaz_app/data/repositories/assessment_repository.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/tutor/gap_suggest_request.dart';
import 'package:dilbaz_app/data/tutor/tutor_providers.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'gap_suggester.g.dart';

/// Who captures, in which course, with what settings.
typedef GapLearner = ({
  String userId,
  StudiedCourse course,
  StudySettings settings,
});

/// The signed-in learner's course and settings; null before the welcome
/// flow.
@riverpod
Future<GapLearner?> gapLearner(Ref ref) async {
  final userId = ref.watch(authRepositoryProvider).userId;
  if (userId == null) return null;
  final course = await ref.watch(assessmentRepositoryProvider).course(userId);
  final settings = await ref
      .watch(profileRepositoryProvider)
      .studySettings(userId);
  if (course == null || settings == null) return null;
  return (userId: userId, course: course, settings: settings);
}

/// Asks `gap_suggest` for a capture and keeps the answer with it
/// (docs/07-ai-tutor.md §4.3). Without an answer the capture waits.
class GapSuggester {
  const new(this._gaps, this._tutor);

  final GapRepository _gaps;
  final TutorRepository _tutor;

  Future<Result<GapSuggestion, TutorFailure>> suggest(
    GapEntry entry,
    GapLearner learner,
  ) async {
    final level = learner.course.level;
    final result = await _tutor.gapSuggest(
      GapSuggestRequest(
        l1: learner.settings.l1,
        l2: learner.course.l2,
        level: level,
        explainInL1: Scaffolds.forLevel(level).explainInL1,
        l1Text: entry.l1Text,
        context: entry.context,
        note: entry.note,
      ),
    );
    if (result case Ok(:final value)) {
      await _gaps.saveSuggestion(entry.id, value);
    }
    return result;
  }

  /// Asks again for the captures still waiting, oldest first, until one
  /// fails: the rest wait for the next time.
  Future<void> catchUp(List<GapEntry> entries, GapLearner learner) async {
    final waiting = entries.reversed.where(
      (entry) => entry.status == GapStatus.fresh && entry.suggestion == null,
    );
    for (final entry in waiting) {
      if (await suggest(entry, learner) is Err) return;
    }
  }
}

@riverpod
GapSuggester gapSuggester(Ref ref) => GapSuggester(
  ref.watch(gapRepositoryProvider),
  ref.watch(tutorRepositoryProvider),
);
