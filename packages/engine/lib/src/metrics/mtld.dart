/// Lexical diversity as MTLD (McCarthy & Jarvis, 2010): the mean length of
/// the stretches of [tokens] over which the type-token ratio stays above
/// [threshold], read forwards and backwards. Null when it cannot be told:
/// no tokens, or no stretch ever ends.
double? mtld(List<String> tokens, {double threshold = 0.72}) {
  if (tokens.isEmpty) return null;
  final forward = _factors(tokens, threshold);
  final backward = _factors(tokens.reversed, threshold);
  if (forward == 0 || backward == 0) return null;
  return (tokens.length / forward + tokens.length / backward) / 2;
}

/// The number of stretches: whole ones, and the share of the last one.
double _factors(Iterable<String> tokens, double threshold) {
  var factors = 0.0;
  final types = <String>{};
  var count = 0;
  var ratio = 1.0;
  for (final token in tokens) {
    count++;
    types.add(token);
    ratio = types.length / count;
    if (ratio <= threshold) {
      factors++;
      types.clear();
      count = 0;
      ratio = 1;
    }
  }
  if (count > 0) factors += (1 - ratio) / (1 - threshold);
  return factors;
}
