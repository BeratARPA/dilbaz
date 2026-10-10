import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'progress_view.freezed.dart';

/// A can-do as the Progress tab lists it (docs/04 §5).
typedef CanDoView = ({String summary, CanDoStatus status, bool refresh});

/// Which recording of an anchor task.
enum AnchorMoment {
  /// The first one: the baseline, or the first monthly test.
  first,

  /// The latest of an earlier month.
  previous,

  /// The latest.
  latest,
}

/// A recording to listen to: when it was made and where it is.
typedef AnchorRecording = ({AnchorMoment moment, DateTime day, String path});

/// One month of an anchor task: its measures, as counts and rates.
typedef MonthRow = ({
  DateTime month,
  double? speechRate,
  double? longPausesPerMin,
  int? clauses,
  int? errorFree,
});

/// An anchor task over the months: before/after listening and the trend
/// (docs/06 §3.4, docs/09 §5.11).
@freezed
abstract class AnchorView with _$AnchorView {
  const factory({
    required String title,
    @Default(<AnchorRecording>[]) List<AnchorRecording> recordings,

    /// Oldest first.
    @Default(<MonthRow>[]) List<MonthRow> months,
  }) = _AnchorView;
}

/// What the Progress tab shows (docs/09 §5.11, v1): evidence counts, the
/// can-dos, and the monthly recordings. Counts and ranges, never a made-up
/// percentage (I-04).
@freezed
abstract class ProgressView with _$ProgressView {
  const factory({
    required EvidenceCounts counts,

    /// Words recognized by the latest placement test (X_Lex), if any.
    int? vocabulary,
    @Default(<CanDoView>[]) List<CanDoView> canDos,
    @Default(<AnchorView>[]) List<AnchorView> anchors,

    /// No test recording with speech in it yet: the baseline is offered
    /// (docs/06 §2 part 4).
    @Default(false) bool offerBaseline,
  }) = _ProgressView;
}
