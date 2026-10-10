/// Evidence level of an item's production (docs/04-learner-model.md §3).
///
/// Levels are projections of the attempt log, never stored judgements
/// (I-04). [transferred] needs free production and is not computed from
/// cards.
enum ItemLevel {
  /// No card yet.
  unseen('new'),

  /// A card exists, but no recall that has held for a week.
  learning('learning'),

  /// Recalled, with a stability of a week or more.
  recallable('recallable'),

  /// Stable for a month, with a spaced recall on the first try lately.
  durable('durable'),

  /// Used without error in free production on two days.
  transferred('transferred');

  new(this.code);

  /// Stable code shown in data and logs.
  final String code;

  /// Whether this level is [other] or higher.
  bool isAtLeast(ItemLevel other) => index >= other.index;
}
