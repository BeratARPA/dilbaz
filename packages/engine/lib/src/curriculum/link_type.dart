/// Edge type of the curriculum graph (docs/02-curriculum.md §4.2).
enum LinkType {
  /// Prerequisite: `to` must be recallable before `from` is introduced.
  requires('requires'),

  /// A sentence contains a chunk, word sense or grammar point.
  contains('contains'),

  /// Easily confused pair; interleaved after first learning (I-10).
  contrastsWith('contrasts_with'),

  /// The item supports a can-do or a task.
  supports('supports'),

  /// Another form of the same meaning.
  variantOf('variant_of'),

  /// A sentence exemplifies a grammar point.
  exampleOf('example_of');

  new(this.code);

  /// Code used in packs (`links.jsonl`).
  final String code;
}
