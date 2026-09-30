/// What H1 of a templated hint ladder names: the kind of difference
/// (docs/03-activities.md §0.5). The app words it from the ARB file.
enum HintKind {
  /// A word is missing.
  missingWord,

  /// There is a word too many.
  extraWord,

  /// A word is in the wrong form.
  wrongForm,

  /// The words are in the wrong order.
  wordOrder,

  /// The answer does not say what the prompt asks.
  meaning,
}
