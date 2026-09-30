/// Skills that have a level estimate of their own
/// (docs/04-learner-model.md §7).
enum Skill {
  /// Recognition vocabulary.
  vocabulary('vocabulary'),

  /// Grammar.
  grammar('grammar'),

  /// Listening.
  listening('listening'),

  /// Reading.
  reading('reading'),

  /// Speaking.
  speaking('speaking'),

  /// Writing.
  writing('writing');

  new(this.code);

  /// Key of the skill in `courses.level_estimates`.
  final String code;
}
