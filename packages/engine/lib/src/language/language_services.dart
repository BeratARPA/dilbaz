/// Language-specific operations, answered from pack data rather than code
/// (I-15, docs/11-language-packs.md §6).
abstract interface class LanguageServices {
  /// [text] in the normalized form answers are compared in.
  String normalize(String text);

  /// Words of [text] after normalization.
  List<String> tokenize(String text);

  /// Lemmas that [token] is a form of; the token itself when unknown.
  Set<String> lemmasOf(String token);

  /// Whether [token] is a word form the pack knows.
  bool knows(String token);

  /// Whether [word] is a hesitation sound ("uh"), as speech recognition
  /// writes it (`normalization.yaml` fillers).
  bool isFiller(String word);
}
