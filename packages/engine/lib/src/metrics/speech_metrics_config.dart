import 'package:freezed_annotation/freezed_annotation.dart';

part 'speech_metrics_config.freezed.dart';

/// Thresholds of the speech measures (docs/06-assessment.md §3.3). They
/// stay the same every month, so that months compare.
@freezed
abstract class SpeechMetricsConfig with _$SpeechMetricsConfig {
  /// Creates the thresholds; the defaults are the documented values.
  const factory({
    /// A silence between words this long is a pause (De Jong & Bosker,
    /// 2013).
    @Default(Duration(milliseconds: 250)) Duration silentPause,

    /// A silence this long is a long pause.
    @Default(Duration(seconds: 1)) Duration longPause,

    /// MTLD's type-token ratio for a factor (McCarthy & Jarvis, 2010).
    @Default(0.72) double mtldThreshold,

    /// Fewer words than this give no MTLD: too little data.
    @Default(100) int mtldMinWords,

    /// Words of lemmas ranked above this are beyond the frequent words.
    @Default(2000) int frequentRank,
  }) = _SpeechMetricsConfig;
}
