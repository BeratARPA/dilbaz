import 'package:json_annotation/json_annotation.dart';

/// How much evidence stands behind a level estimate
/// (docs/04-learner-model.md §7).
@JsonEnum(valueField: 'code')
enum Confidence {
  /// Fewer than five evidence points, or the newest older than 90 days.
  low('low'),

  /// Between low and high.
  medium('medium'),

  /// At least 15 consistent evidence points in the last 60 days.
  high('high');

  new(this.code);

  /// Code stored in `courses.level_estimates`.
  final String code;
}
