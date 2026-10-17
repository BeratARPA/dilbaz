import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  // Synthetic words: `mi` and `ta` are frequent (function words), `bada`
  // has a form with an ending (`badan`) and one that is another stem
  // (`ubada`), `kolu` and `kolo` are a letter apart.
  final language = PackLanguage(
    rules: const NormalizationRules(version: 1, punctuation: '.,?!'),
    forms: {
      'mi': {'mi'},
      'ta': {'ta'},
      'bada': {'bada'},
      'badan': {'bada'},
      'ubada': {'bada'},
      'kolu': {'kolu'},
      'kolo': {'kolo'},
      'søravelin': {'søravelin'},
    },
  );
  const ranks = {'mi': 3, 'ta': 12, 'bada': 900, 'kolu': 1500, 'kolo': 2000};

  DictationCheck check(String expected, String typed) => DictationCheck.of(
    expected: expected,
    typed: typed,
    language: language,
    rankOf: (lemma) => ranks[lemma],
  );

  group('DictationCheck (A05)', () {
    test('heard as said: every word heard, no error, Good', () {
      final result = check('Bada mi kolu.', 'bada mi kolu');
      expect(result.words, ['bada', 'mi', 'kolu']);
      expect(result.marks, everyElement(DictationMark.heard));
      expect(result.errors, 0);
      expect(result.errorRate, 0);
      expect(result.rating(), ReviewRating.good);
    });

    test('a missed or changed frequent word is a weak form', () {
      expect(check('bada mi kolu', 'bada kolu').marks, [
        DictationMark.heard,
        DictationMark.weakForm,
        DictationMark.heard,
      ]);
      expect(
        check('bada mi kolu', 'bada ta kolu').marks[1],
        DictationMark.weakForm,
      );
    });

    test('a missed or changed rarer word is missed or changed', () {
      expect(check('bada mi kolu', 'bada mi').marks[2], DictationMark.missed);
      // `kolo` is a real word: what was heard, not a slip.
      expect(
        check('bada mi kolu', 'bada mi kolo').marks[2],
        DictationMark.changed,
      );
    });

    test('the same word with another ending is an ending not heard', () {
      expect(
        check('badan kolu', 'bada kolu').marks.first,
        DictationMark.ending,
      );
      expect(
        check('bada kolu', 'badan kolu').marks.first,
        DictationMark.ending,
      );
      // Same lemma, but not an ending: another form.
      expect(
        check('badan kolu', 'ubada kolu').marks.first,
        DictationMark.changed,
      );
    });

    test('a misspelling that is no word is a slip and no error', () {
      final result = check('bada søravelin', 'bada søravlin');
      expect(result.marks.last, DictationMark.slip);
      expect(result.errors, 0);
      expect(result.rating(), ReviewRating.good);
    });

    test('words too many and words out of order count', () {
      final extra = check('bada kolu', 'bada mi kolu');
      expect(extra.extra, ['mi']);
      expect(extra.errors, 1);
      final swapped = check('bada mi kolu', 'mi bada kolu');
      expect(swapped.marks.take(2), everyElement(DictationMark.changed));
    });

    test('Hard up to a quarter of the words wrong, Again above', () {
      expect(
        check('bada mi kolu ta', 'bada mi kolu').rating(),
        ReviewRating.hard,
      );
      expect(check('bada mi kolu ta', 'bada').rating(), ReviewRating.again);
      expect(check('', '').errorRate, 0);
    });

    test('without ranks no word counts as a function word', () {
      final result = DictationCheck.of(
        expected: 'bada mi kolu',
        typed: 'bada kolu',
        language: language,
      );
      expect(result.marks[1], DictationMark.missed);
    });
  });

  group('pickDictations (A05, I-06)', () {
    const a1 = CefrLevel.a1;
    const a2 = CefrLevel.a2;
    const b1 = CefrLevel.b1;
    final candidates = <DictationCandidate>[
      (key: 's.a1.one', lemmas: ['bada'], level: a1),
      (key: 's.a1.two', lemmas: ['kolu'], level: a1),
      (key: 's.a2.one', lemmas: ['bada', 'mi'], level: a2),
      (key: 's.a2.hard', lemmas: ['zorlu'], level: a2),
      (key: 's.b1.one', lemmas: ['bada'], level: b1),
    ];
    double coverage(Iterable<String> lemmas) =>
        lemmas.contains('zorlu') ? 0.5 : 1;

    test('due cards first, then new ones the learner can understand', () {
      final picked = pickDictations(
        candidates: candidates,
        coverage: coverage,
        level: a2,
        seed: 1,
        due: ['s.a1.two', 'gone'],
        carded: {'s.a1.two'},
      );
      expect(picked.first, 's.a1.two');
      // Low coverage and above the level are left out; the level first.
      expect(picked.skip(1).toList(), ['s.a2.one', 's.a1.one']);
    });

    test('a count in all, a few new at most', () {
      expect(
        pickDictations(
          candidates: candidates,
          coverage: coverage,
          level: b1,
          seed: 1,
          count: 2,
        ),
        hasLength(2),
      );
      expect(
        pickDictations(
          candidates: candidates,
          coverage: coverage,
          level: b1,
          seed: 1,
          newCount: 1,
        ),
        ['s.b1.one'],
      );
      expect(
        pickDictations(
          candidates: candidates,
          coverage: coverage,
          level: a2,
          seed: 1,
          due: ['s.a1.one', 's.a1.two', 's.a2.one'],
          count: 2,
        ),
        ['s.a1.one', 's.a1.two'],
      );
    });

    test('below A1 the A1 sentences are taken', () {
      expect(
        pickDictations(
          candidates: candidates,
          coverage: coverage,
          level: CefrLevel.a0,
          seed: 1,
        ).toSet(),
        {'s.a1.one', 's.a1.two'},
      );
    });
  });
}
