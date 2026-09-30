import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  // A handful of synthetic words: a lemma with a second form, two words a
  // letter apart, a short and a long word, and letters outside ASCII.
  final language = PackLanguage(
    rules: const NormalizationRules(version: 1, punctuation: '.,?!'),
    forms: {
      'mi': {'mi'},
      'bada': {'bada'},
      'badan': {'bada'},
      'kolu': {'kolu'},
      'kolo': {'kolo'},
      'tåme': {'tåme'},
      'ʒorin': {'ʒorin'},
      'søravelin': {'søravelin'},
    },
  );

  DictationScore score(String expected, String typed) =>
      DictationScore.of(expected: expected, typed: typed, language: language);

  group('DictationScore (docs/06-assessment.md §2, part 3)', () {
    test('what was heard right has no errors', () {
      final result = score('Bada kolu mi.', 'bada  kolu mi');
      expect(result, const DictationScore(words: 3, errors: 0, slips: 0));
      expect(result.errorRate, 0);
    });

    test('a missing, an added and a changed word are one error each', () {
      expect(score('bada kolu mi', 'bada mi').errors, 1);
      expect(score('bada kolu mi', 'bada kolu tåme mi').errors, 1);
      expect(score('bada kolu mi', 'bada ʒorin mi').errors, 1);
      expect(score('bada kolu mi', 'bada mi').errorRate, closeTo(1 / 3, 1e-9));
    });

    test('another real word is what the learner heard: an error', () {
      // `kolo` is a word of the language, one letter from `kolu`.
      final result = score('bada kolu mi', 'bada kolo mi');
      expect(result.errors, 1);
      expect(result.slips, 0);
    });

    test('another form of the word is an error: the ending was missed', () {
      final result = score('badan kolu', 'bada kolu');
      expect(result.errors, 1);
      expect(result.slips, 0);
    });

    test('a misspelling that is no word is a slip, not an error', () {
      final wrongLetter = score('bada kolu mi', 'bada kolv mi');
      expect(wrongLetter, const DictationScore(words: 3, errors: 0, slips: 1));

      expect(score('bada kolu mi', 'bada koul mi').slips, 1, reason: 'swap');
      expect(score('bada kolu mi', 'bada kollu mi').slips, 1, reason: 'added');
      expect(score('bada ʒorin', 'bada ʒrin').slips, 1, reason: 'left out');
    });

    test('letters outside ASCII count as one letter', () {
      final result = score('tåme kolu', 'tame kolu');
      expect(result.errors, 0);
      expect(result.slips, 1);
    });

    test('short words have no room for slips', () {
      final result = score('bada mi', 'bada mu');
      expect(result.errors, 1);
      expect(result.slips, 0);
    });

    test('two wrong letters are a slip only in a long word', () {
      expect(score('bada ʒorin', 'bada ʒaran').errors, 1);
      final long = score('bada søravelin', 'bada soravelen');
      expect(long.errors, 0);
      expect(long.slips, 1);
      expect(score('bada søravelin', 'bada soravalen').errors, 1);
    });

    test('nothing written misses every word', () {
      final result = score('bada kolu mi', '');
      expect(result.errors, 3);
      expect(result.errorRate, 1);
    });

    test('the error rate never passes 1', () {
      final result = score('mi', 'bada kolu tåme ʒorin');
      expect(result.errors, greaterThan(1));
      expect(result.errorRate, 1);
    });

    test('a sentence without words has no error rate to speak of', () {
      expect(score('...', '').errorRate, 0);
    });

    test('the settings move the limits', () {
      final strict = DictationScore.of(
        expected: 'bada kolu',
        typed: 'bada kolv',
        language: language,
        config: const DictationConfig(slipLength: 5),
      );
      expect(strict.errors, 1);
    });
  });

  group('DictationScore.estimate', () {
    const a1 = CefrLevel.a1;
    const a2 = CefrLevel.a2;
    const clean = DictationScore(words: 5, errors: 0, slips: 0);

    test('pools the sentences of a level', () {
      // A1: 1 error in 11 words; A2: 2 in 8.
      final estimate = DictationScore.estimate([
        (a1, clean),
        (a1, const DictationScore(words: 6, errors: 1, slips: 0)),
        (a2, const DictationScore(words: 8, errors: 2, slips: 0)),
      ], source: 'placement');
      expect(estimate, LevelEstimate.at(a1, source: 'placement'));
    });

    test('a level is reached up to 15% errors', () {
      const atLimit = DictationScore(words: 20, errors: 3, slips: 0);
      const over = DictationScore(words: 20, errors: 4, slips: 0);
      expect(
        DictationScore.estimate([(a1, clean), (a2, atLimit)]),
        LevelEstimate.between(a2, CefrLevel.c2),
      );
      expect(
        DictationScore.estimate([(a1, clean), (a2, over)]),
        LevelEstimate.at(a1),
      );
    });

    test('the lowest level missed: the level under it', () {
      const lost = DictationScore(words: 5, errors: 3, slips: 0);
      expect(
        DictationScore.estimate([(a1, lost), (a2, lost)]),
        LevelEstimate.at(CefrLevel.a0),
      );
    });

    test('slips do not count against a level', () {
      const slipped = DictationScore(words: 5, errors: 0, slips: 2);
      expect(
        DictationScore.estimate([(a1, slipped)]),
        LevelEstimate.between(a1, CefrLevel.c2),
      );
    });

    test('without sentences there is nothing to estimate', () {
      expect(() => DictationScore.estimate(const []), throwsArgumentError);
    });
  });
}
