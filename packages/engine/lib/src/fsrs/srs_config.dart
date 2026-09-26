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

  /// Settings for replaying attempts deterministically (fuzz off).
  static const replay = SrsConfig(enableFuzzing: false);

  /// Lowest desired retention accepted (`courses.desired_retention`).
  static const minDesiredRetention = 0.80;

  /// Highest desired retention accepted (`courses.desired_retention`).
  static const maxDesiredRetention = 0.97;
}
