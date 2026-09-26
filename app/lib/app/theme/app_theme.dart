import 'package:dilbaz_app/app/theme/feedback_colors.dart';
import 'package:flutter/material.dart';

/// Material 3 themes (docs/09-ux-motivation.md §3).
///
/// A calm blue-green primary. The error role is a soft orange so that no
/// screen or banner turns red. Card prompts use `headlineSmall` (24 sp) or
/// larger.
abstract final class AppTheme {
  static const seed = Color(0xFF1F7A74);

  static ThemeData light() => _theme(
    ColorScheme.fromSeed(
      seedColor: seed,
      error: const Color(0xFFB45309),
      onError: const Color(0xFFFFFFFF),
      errorContainer: const Color(0xFFFFEDD5),
      onErrorContainer: const Color(0xFF7A3E0C),
    ),
    FeedbackColors.light,
  );

  static ThemeData dark() => _theme(
    ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      error: const Color(0xFFFDBA74),
      onError: const Color(0xFF431407),
      errorContainer: const Color(0xFF7A3E0C),
      onErrorContainer: const Color(0xFFFFEDD5),
    ),
    FeedbackColors.dark,
  );

  static ThemeData _theme(ColorScheme scheme, FeedbackColors feedback) =>
      ThemeData(colorScheme: scheme, extensions: [feedback]);
}
