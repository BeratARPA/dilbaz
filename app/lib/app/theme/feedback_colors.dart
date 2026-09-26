import 'package:flutter/material.dart';

/// Colors of answer feedback (docs/09-ux-motivation.md §3).
///
/// Correct is green, "almost" is amber and in-text error highlights are a
/// soft orange. There is no red. Color is never the only signal: every state
/// also has an icon and a text.
@immutable
class FeedbackColors extends ThemeExtension<FeedbackColors> {
  const new({
    required this.correct,
    required this.nearMiss,
    required this.errorHighlight,
  });

  static const light = FeedbackColors(
    correct: Color(0xFF2E7D32),
    nearMiss: Color(0xFF9A6700),
    errorHighlight: Color(0xFFFFDDBF),
  );

  static const dark = FeedbackColors(
    correct: Color(0xFF81C784),
    nearMiss: Color(0xFFFFD54F),
    errorHighlight: Color(0xFF6B3A12),
  );

  /// Icons and text of a correct answer.
  final Color correct;

  /// Icons and text of an "almost" answer.
  final Color nearMiss;

  /// Background behind the erroneous span of a learner's answer.
  final Color errorHighlight;

  @override
  FeedbackColors copyWith({
    Color? correct,
    Color? nearMiss,
    Color? errorHighlight,
  }) => FeedbackColors(
    correct: correct ?? this.correct,
    nearMiss: nearMiss ?? this.nearMiss,
    errorHighlight: errorHighlight ?? this.errorHighlight,
  );

  @override
  FeedbackColors lerp(FeedbackColors? other, double t) {
    if (other == null) return this;
    return FeedbackColors(
      correct: Color.lerp(correct, other.correct, t)!,
      nearMiss: Color.lerp(nearMiss, other.nearMiss, t)!,
      errorHighlight: Color.lerp(errorHighlight, other.errorHighlight, t)!,
    );
  }
}
