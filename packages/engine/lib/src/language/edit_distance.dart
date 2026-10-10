import 'dart:math';

/// How many single edits turn [a] into [b]: a letter typed wrong, left out
/// or added, or two neighbouring letters swapped (optimal string alignment).
///
/// Letters are Unicode code points, so the count holds for any script.
int editDistance(String a, String b) {
  final from = a.runes.toList();
  final to = b.runes.toList();
  final distance = [
    [for (var j = 0; j <= to.length; j++) j],
    for (var i = 1; i <= from.length; i++) List.filled(to.length + 1, i),
  ];
  for (var i = 1; i <= from.length; i++) {
    for (var j = 1; j <= to.length; j++) {
      final same = from[i - 1] == to[j - 1];
      var best = min(distance[i - 1][j], distance[i][j - 1]) + 1;
      best = min(best, distance[i - 1][j - 1] + (same ? 0 : 1));
      if (i > 1 &&
          j > 1 &&
          from[i - 1] == to[j - 2] &&
          from[i - 2] == to[j - 1]) {
        best = min(best, distance[i - 2][j - 2] + 1);
      }
      distance[i][j] = best;
    }
  }
  return distance[from.length][to.length];
}
