import 'package:dilbaz_engine/src/fsrs/mode_group.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'srs_config.freezed.dart';

/// Scheduler settings for one mode group (production, receptive, dictation).
@freezed
abstract class SrsConfig with _$SrsConfig {
  /// Creates scheduler settings. The defaults are the live settings.
  const factory({
    /// Target probability of recall when a card becomes due.
    @Default(0.90) double desiredRetention,

    /// 21 FSRS-6 weights; null uses the FSRS defaults (docs/04 §2).
    List<double>? parameters,

    /// Interval fuzzing. On in live use, off when replaying attempts.
    @Default(true) bool enableFuzzing,
  }) = _SrsConfig;

  /// Live settings for one mode [group] of a course (docs/13-data-model.md
  /// §2): `courses.fsrs_params` keeps personal weights per group, and a
  /// group without weights uses the FSRS defaults.
  factory forCourse({
    required ModeGroup group,
    required double desiredRetention,
    Map<String, Object?>? fsrsParams,
  }) => SrsConfig(
    desiredRetention: desiredRetention,
    parameters: switch (fsrsParams?[group.code]) {
      null => null,
      // jsonb may keep 3.0 as 3.
      final List<Object?> weights => [
        for (final weight in weights)
          if (weight is num)
            weight.toDouble()
          else
            throw ArgumentError.value(weight, 'fsrsParams', 'not_a_number'),
      ],
      final Object other => throw ArgumentError.value(
        other,
        'fsrsParams',
        'not_a_list',
      ),
    },
  );

  /// Settings for replaying attempts deterministically (fuzz off).
  static const replay = SrsConfig(enableFuzzing: false);

  /// Lowest desired retention accepted (`courses.desired_retention`).
  static const minDesiredRetention = 0.80;

  /// Highest desired retention accepted (`courses.desired_retention`).
  static const maxDesiredRetention = 0.97;
}
