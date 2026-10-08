import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/planner/strand.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'learner_snapshot.freezed.dart';

/// What the planner needs to know about the learner today
/// (docs/04-learner-model.md §8).
@freezed
abstract class LearnerSnapshot with _$LearnerSnapshot {
  /// Creates a snapshot.
  const factory({
    /// The learner's level, for the caps and targets that depend on it.
    required CefrLevel level,

    /// Time the learner wants to spend a day (I-13).
    @Default(Duration(minutes: 30)) Duration dailyBudget,

    /// Time already spent today.
    @Default(Duration.zero) Duration spentToday,

    /// New items already introduced today; the day's cap counts them.
    @Default(0) int newToday,

    /// Share of first-try recalls among the reviews of the last seven
    /// days; null without any.
    double? recentUnaidedAccuracy,

    /// Time spent this week, by strand.
    @Default(<Strand, Duration>{}) Map<Strand, Duration> weekStrandTime,

    /// Silent mode: the learner types instead of speaking.
    @Default(false) bool silentMode,
  }) = _LearnerSnapshot;
}
