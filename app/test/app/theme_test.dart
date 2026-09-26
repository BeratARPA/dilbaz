import 'package:dilbaz_app/app/theme/app_theme.dart';
import 'package:dilbaz_app/app/theme/feedback_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double hueOf(Color color) => HSLColor.fromColor(color).hue;

void main() {
  final themes = {'light': AppTheme.light(), 'dark': AppTheme.dark()};

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    group('$name theme', () {
      test('is Material 3 with the matching brightness', () {
        expect(theme.useMaterial3, isTrue);
        expect(
          theme.colorScheme.brightness,
          name == 'dark' ? Brightness.dark : Brightness.light,
        );
      });

      test('error colors are soft orange, never red (docs/09 §3)', () {
        final scheme = theme.colorScheme;
        for (final color in [scheme.error, scheme.errorContainer]) {
          expect(hueOf(color), inInclusiveRange(20, 45));
        }
      });

      test('feedback colors: green correct, amber near miss, orange '
          'highlight', () {
        final feedback = theme.extension<FeedbackColors>()!;
        expect(hueOf(feedback.correct), inInclusiveRange(90, 150));
        expect(hueOf(feedback.nearMiss), inInclusiveRange(38, 55));
        expect(hueOf(feedback.errorHighlight), inInclusiveRange(20, 45));
      });
    });
  }

  test('feedback colors interpolate for theme animations', () {
    final mid = FeedbackColors.light.lerp(FeedbackColors.dark, 0.5);
    expect(mid.correct, isNot(FeedbackColors.light.correct));
    expect(FeedbackColors.light.lerp(null, 0.5), FeedbackColors.light);
    expect(
      FeedbackColors.light.copyWith(correct: FeedbackColors.dark.correct),
      isA<FeedbackColors>().having(
        (c) => c.correct,
        'correct',
        FeedbackColors.dark.correct,
      ),
    );
  });
}
