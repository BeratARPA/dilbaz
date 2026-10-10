import 'package:dilbaz_engine/src/speaking/speech_annotation.dart';

/// The corrections a speaking task practises, at most [count] (docs/03
/// A11 step 4b, I-02: at most three).
///
/// Those with one of the learner's [persistentTags] come first (docs/04
/// §6), then those that break the meaning (severity 3), then those whose
/// tag came up most in this transcript; ties keep the annotation's order.
/// A sentence is practised once.
List<SpeechCorrection> pickCorrections(
  SpeechAnnotation annotation, {
  Set<String> persistentTags = const {},
  int count = 3,
}) {
  final often = <String, int>{};
  for (final error in annotation.errors) {
    often[error.tag] = (often[error.tag] ?? 0) + 1;
  }
  final said = <String>{};
  final candidates = [
    for (final (i, correction) in annotation.corrections.indexed)
      if (said.add(correction.original.trim())) (i, correction),
  ];
  int persistent(SpeechCorrection c) => persistentTags.contains(c.tag) ? 1 : 0;
  int breaking(SpeechCorrection c) => c.severity >= 3 ? 1 : 0;
  int frequent(SpeechCorrection c) => often[c.tag] ?? 0;
  candidates.sort((a, b) {
    for (final key in [persistent, breaking, frequent]) {
      final order = key(b.$2) - key(a.$2);
      if (order != 0) return order;
    }
    return a.$1 - b.$1;
  });
  return [for (final (_, correction) in candidates.take(count)) correction];
}
