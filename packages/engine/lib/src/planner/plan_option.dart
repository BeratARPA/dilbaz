import 'package:dilbaz_engine/src/planner/strand.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'plan_option.freezed.dart';

/// An activity the learner may choose after the cards
/// (docs/05-session-planner.md §3–4): a candidate going in, an option
/// coming out.
@freezed
abstract class PlanOption with _$PlanOption {
  /// Creates an option.
  const factory({
    /// Activity id, as in `attempts.activity`.
    required String activity,

    /// The strand its time counts for.
    required Strand strand,

    /// How long it takes.
    required Duration duration,

    /// Key of the task or text it is about, when it has one.
    String? ref,

    /// Supports a can-do the learner has not shown yet.
    @Default(false) bool supportsUnprovenCanDo,

    /// Tied to the weekly error focus.
    @Default(false) bool focus,

    /// Not done in the last three days.
    @Default(false) bool fresh,

    /// Done together with the partner.
    @Default(false) bool together,
  }) = _PlanOption;
}
