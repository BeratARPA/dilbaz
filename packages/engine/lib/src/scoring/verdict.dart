/// Verdict on one production answer (docs/03-activities.md §0.2).
///
/// [code] is the value stored in `attempts.verdict` and returned by the
/// `answer_check` route.
enum Verdict {
  /// Matches the reference or a known variant.
  correct('correct'),

  /// Another natural and correct answer (I-17).
  acceptableVariant('acceptable_variant'),

  /// Meaning kept, with a small form error.
  minorError('minor_error'),

  /// The target structure or meaning is wrong.
  wrong('wrong'),

  /// Something else was said.
  offTarget('off_target'),

  /// Speech recognition gave nothing meaningful.
  unintelligible('unintelligible'),

  /// The evaluator could not decide.
  uncertain('uncertain');

  new(this.code);

  /// Stable code shared with the database and the LLM routes.
  final String code;
}
