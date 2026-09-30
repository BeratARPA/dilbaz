/// A strand of the course (docs/03-activities.md §0.1); the planner keeps
/// the week's time across the first four in balance (docs/05 §2).
enum Strand {
  /// Meaning-focused input.
  input('input'),

  /// Meaning-focused output.
  output('output'),

  /// Language-focused learning.
  language('language'),

  /// Fluency development.
  fluency('fluency'),

  /// Metacognition; has no weekly target.
  meta('meta');

  new(this.code);

  /// Code used in `sessions.strand_ms` and in activity definitions.
  final String code;
}
