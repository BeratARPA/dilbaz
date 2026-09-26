/// Kind of a learnable item node (docs/02-curriculum.md §4.1).
enum ItemKind {
  /// Carrier sentence.
  sentence('sentence'),

  /// Chunk or collocation.
  chunk('chunk'),

  /// One sense of a word.
  wordSense('word_sense'),

  /// Grammar structure.
  grammarPoint('grammar_point'),

  /// Sound or sound contrast.
  sound('sound'),

  /// Syntactic pattern.
  pattern('pattern');

  new(this.code);

  /// Code used in packs and in the database.
  final String code;
}
