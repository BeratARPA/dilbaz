import 'dart:math';

import 'package:dilbaz_engine/src/language/word_diff.dart';

/// Word-level alignment of an answer with an expected text
/// (docs/03-activities.md §0.5, step 4).
///
/// The alignment has the least cost: the expected word in another form
/// costs 1; another word, a missing or an extra word, or two swapped
/// neighbours cost 2. A missing word that turns up elsewhere in the answer
/// counts as one change of order.
final class WordAlignment {
  /// Aligns [actual] with [expected]; [sameLemma] tells two different words
  /// that are forms of one lemma.
  factory of(
    List<String> expected,
    List<String> actual, {
    required bool Function(String expected, String actual) sameLemma,
  }) {
    int substitution(int e, int a) => expected[e] == actual[a]
        ? 0
        : sameLemma(expected[e], actual[a])
        ? _formCost
        : _changeCost;
    bool swapped(int i, int j) =>
        i >= 2 &&
        j >= 2 &&
        expected[i - 1] == actual[j - 2] &&
        expected[i - 2] == actual[j - 1] &&
        expected[i - 1] != expected[i - 2];

    final n = expected.length;
    final m = actual.length;
    final cost = [
      [for (var j = 0; j <= m; j++) j * _changeCost],
      for (var i = 1; i <= n; i++) List.filled(m + 1, 0),
    ];
    for (var i = 1; i <= n; i++) {
      cost[i][0] = i * _changeCost;
      for (var j = 1; j <= m; j++) {
        var best = min(cost[i - 1][j], cost[i][j - 1]) + _changeCost;
        best = min(best, cost[i - 1][j - 1] + substitution(i - 1, j - 1));
        if (swapped(i, j)) best = min(best, cost[i - 2][j - 2] + _changeCost);
        cost[i][j] = best;
      }
    }

    final aligned = <int, int>{};
    final diffs = <WordDiff>[];
    var i = n;
    var j = m;
    while (i > 0 || j > 0) {
      if (i > 0 &&
          j > 0 &&
          expected[i - 1] == actual[j - 1] &&
          cost[i][j] == cost[i - 1][j - 1]) {
        aligned[--i] = --j;
      } else if (swapped(i, j) &&
          cost[i][j] == cost[i - 2][j - 2] + _changeCost) {
        i -= 2;
        j -= 2;
        aligned[i] = j + 1;
        aligned[i + 1] = j;
        diffs.add(
          WordDiff(
            kind: WordDiffKind.order,
            expected: [i, i + 1],
            actual: [j, j + 1],
          ),
        );
      } else if (i > 0 &&
          j > 0 &&
          cost[i][j] == cost[i - 1][j - 1] + substitution(i - 1, j - 1)) {
        aligned[--i] = --j;
        diffs.add(
          WordDiff(
            kind: substitution(i, j) == _formCost
                ? WordDiffKind.form
                : WordDiffKind.other,
            expected: [i],
            actual: [j],
          ),
        );
      } else if (i > 0 && cost[i][j] == cost[i - 1][j] + _changeCost) {
        diffs.add(WordDiff(kind: WordDiffKind.missing, expected: [--i]));
      } else {
        diffs.add(WordDiff(kind: WordDiffKind.extra, actual: [--j], before: i));
      }
    }
    return WordAlignment._(
      expected: expected,
      actual: actual,
      aligned: aligned,
      diffs: _withMoves(expected, actual, diffs, aligned),
    );
  }

  const new _({
    required this.expected,
    required this.actual,
    required this.aligned,
    required this.diffs,
  });

  static const _formCost = 1;
  static const _changeCost = 2;

  /// The expected words.
  final List<String> expected;

  /// The answer's words.
  final List<String> actual;

  /// Expected index → index of the answer word in its place: the same word,
  /// another form, another word or the same word moved.
  final Map<int, int> aligned;

  /// The differences, in text order.
  final List<WordDiff> diffs;

  /// Pairs each missing word with the same word extra elsewhere.
  static List<WordDiff> _withMoves(
    List<String> expected,
    List<String> actual,
    List<WordDiff> diffs,
    Map<int, int> aligned,
  ) {
    final extras = [
      for (final diff in diffs)
        if (diff.kind == WordDiffKind.extra) diff,
    ];
    final result = <WordDiff>[];
    for (final diff in diffs) {
      if (diff.kind == WordDiffKind.extra) continue;
      if (diff.kind == WordDiffKind.missing) {
        final word = expected[diff.expected.single];
        final extra = extras
            .where((e) => actual[e.actual.single] == word)
            .firstOrNull;
        if (extra != null) {
          extras.remove(extra);
          aligned[diff.expected.single] = extra.actual.single;
          result.add(
            WordDiff(
              kind: WordDiffKind.order,
              expected: diff.expected,
              actual: extra.actual,
            ),
          );
          continue;
        }
      }
      result.add(diff);
    }
    result.addAll(extras);
    int position(WordDiff diff) =>
        diff.expected.isEmpty ? diff.before! : diff.expected.first;
    return result..sort((a, b) {
      final byPosition = position(a).compareTo(position(b));
      if (byPosition != 0) return byPosition;
      final aActual = a.actual.isEmpty ? -1 : a.actual.first;
      final bActual = b.actual.isEmpty ? -1 : b.actual.first;
      return aActual.compareTo(bActual);
    });
  }
}
