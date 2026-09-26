/// CEFR level; language-independent (docs/02-curriculum.md §1).
enum CefrLevel {
  /// Pre-A1.
  a0('A0'),

  /// Breakthrough.
  a1('A1'),

  /// Waystage.
  a2('A2'),

  /// Threshold.
  b1('B1'),

  /// Vantage.
  b2('B2'),

  /// Effective operational proficiency.
  c1('C1'),

  /// Mastery.
  c2('C2');

  new(this.code);

  /// Code used in packs and in the database.
  final String code;

  /// Numeric scale of the learner model: A0 = 0 … C2 = 6 (docs/04 §7).
  int get scale => index;

  /// Whether this level is at or below [other].
  bool isAtMost(CefrLevel other) => scale <= other.scale;
}
