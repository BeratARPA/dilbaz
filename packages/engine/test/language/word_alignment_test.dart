import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

import '../fixtures/zz/zz_pack.dart';

void main() {
  final zz = ZzPack.generate();
  bool sameLemma(String a, String b) =>
      (zz.forms[a] ?? {a}).any((zz.forms[b] ?? {b}).contains);
  WordAlignment align(List<String> expected, List<String> actual) =>
      WordAlignment.of(expected, actual, sameLemma: sameLemma);

  // Six words that are forms of nothing else; one verb with other forms.
  final plain = [
    for (final entry in zz.lexicon)
      if (zz.forms[entry.lemma]!.length == 1 &&
          zz.forms.entries.where((e) => e.value.contains(entry.lemma)).length ==
              1)
        entry.lemma,
  ].take(6).toList();
  final [a, b, c, d, e, f] = plain;
  final verb = zz.lexicon.firstWhere(
    (entry) => entry.pos == 'VERB' && zz.forms.containsKey('${entry.lemma}mi'),
  );
  final form = '${verb.lemma}mi';

  group('WordAlignment (docs/03-activities.md §0.5, step 4)', () {
    test('the same words align one to one', () {
      final alignment = align([a, b, c], [a, b, c]);
      expect(alignment.diffs, isEmpty);
      expect(alignment.aligned, {0: 0, 1: 1, 2: 2});
    });

    test('finds a missing word', () {
      final alignment = align([a, b, c], [a, c]);
      expect(alignment.diffs, [
        const WordDiff(kind: WordDiffKind.missing, expected: [1]),
      ]);
      expect(alignment.aligned, {0: 0, 2: 1});
    });

    test('finds an extra word and what it stands before', () {
      final alignment = align([a, b, c], [a, b, d, c]);
      expect(alignment.diffs, [
        const WordDiff(kind: WordDiffKind.extra, actual: [2], before: 2),
      ]);
    });

    test('tells another form of the word from another word', () {
      expect(align([a, verb.lemma, c], [a, form, c]).diffs, [
        const WordDiff(kind: WordDiffKind.form, expected: [1], actual: [1]),
      ]);
      expect(align([a, b, c], [a, d, c]).diffs, [
        const WordDiff(kind: WordDiffKind.other, expected: [1], actual: [1]),
      ]);
    });

    test('prefers the form of a word to another word', () {
      expect(align([verb.lemma, b], [form]).diffs, [
        const WordDiff(kind: WordDiffKind.form, expected: [0], actual: [0]),
        const WordDiff(kind: WordDiffKind.missing, expected: [1]),
      ]);
    });

    test('counts two swapped neighbours as one change of order', () {
      final alignment = align([a, b, c, d], [a, c, b, d]);
      expect(alignment.diffs, [
        const WordDiff(
          kind: WordDiffKind.order,
          expected: [1, 2],
          actual: [1, 2],
        ),
      ]);
      expect(alignment.aligned, {0: 0, 1: 2, 2: 1, 3: 3});
    });

    test('counts a word moved far as one change of order', () {
      final alignment = align([a, b, c, d, e], [b, c, d, e, a]);
      expect(alignment.diffs, [
        const WordDiff(kind: WordDiffKind.order, expected: [0], actual: [4]),
      ]);
      expect(alignment.aligned[0], 4);
    });

    test('a repeated word is not a swap', () {
      expect(align([a, a], [a, a]).diffs, isEmpty);
      expect(align([a, a, b], [a, b]).diffs, hasLength(1));
    });

    test('lists differences in text order', () {
      final alignment = align([a, b, c, d, e], [f, b, d, e, c]);
      final positions = [
        for (final diff in alignment.diffs)
          if (diff.expected.isEmpty) diff.before! else diff.expected.first,
      ];
      expect(positions, [...positions]..sort());
    });

    test('aligns with nothing on either side', () {
      expect(align([], [a, b]).diffs, [
        const WordDiff(kind: WordDiffKind.extra, actual: [0], before: 0),
        const WordDiff(kind: WordDiffKind.extra, actual: [1], before: 0),
      ]);
      expect(align([a], []).diffs, [
        const WordDiff(kind: WordDiffKind.missing, expected: [0]),
      ]);
      expect(align([], []).diffs, isEmpty);
    });
  });
}
