import 'package:dilbaz_app/features/speaking/application/speaking_state.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'monthly_state.freezed.dart';

/// A task of the test as its card shows it.
@freezed
abstract class TestStep with _$TestStep {
  const factory({
    required TaskView task,
    required int number,
    required int total,

    /// The same task every month (ANC-1…3).
    required bool anchor,
    required bool recording,
  }) = _TestStep;
}

/// One task in the report: its measures and, for an anchor, last month's.
/// Counts, not percentages (I-04); null while the recording waits.
@freezed
abstract class ReportTask with _$ReportTask {
  const factory({
    required String title,
    required bool anchor,
    Duration? spoken,
    int? words,
    double? speechRate,
    double? longPausesPerMin,
    int? clauses,
    int? errorFree,
    double? previousSpeechRate,
    double? previousLongPausesPerMin,
    int? previousClauses,
    int? previousErrorFree,
  }) = _ReportTask;
}

/// Where the monthly speaking test is (A23, docs/06 §3), or the baseline
/// recording of the placement test (§2 part 4).
@freezed
sealed class MonthlyState with _$MonthlyState {
  /// No course, profile or tasks on the device yet.
  const factory unavailable() = MonthlyUnavailable;

  /// The learner has not agreed to audio recordings (I-18).
  const factory needsConsent() = MonthlyNeedsConsent;

  /// What the test is: how many tasks and how long each may be.
  const factory intro({
    required bool baseline,
    required int tasks,
    required Duration limit,
  }) = MonthlyIntro;

  /// A level check of the microphone before the first task.
  const factory micCheck({required bool listening}) = MonthlyMicCheck;

  const factory task(TestStep step) = MonthlyTask;

  /// The microphone could not be used for this task.
  const factory failed(TestStep step, SpeakingFailure failure) = MonthlyFailed;

  /// Every task is recorded; the last ones are being processed.
  const factory finishing() = MonthlyFinishing;

  const factory report({
    required bool baseline,
    required List<ReportTask> tasks,
  }) = MonthlyReport;
}
