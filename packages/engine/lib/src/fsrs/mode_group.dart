/// Card modes that share one set of FSRS weights
/// (`courses.fsrs_params`, docs/04-learner-model.md §2).
enum ModeGroup {
  /// Spoken or written production.
  production('production'),

  /// Recognition by ear.
  receptive('receptive'),

  /// Dictation.
  dictation('dictation');

  new(this.code);

  /// Key of the group's weights in `courses.fsrs_params`.
  final String code;
}
