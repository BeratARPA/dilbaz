import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

import '../fixtures/zz/zz_pack.dart';

void main() {
  for (final separator in [Normalizer.space, '·']) {
    group('Normalizer, words separated by "$separator"', () {
      final zz = ZzPack.generate(wordSeparator: separator);
      final w = [for (final entry in zz.lexicon) entry.lemma];
      String join(List<String> words) => words.join(separator);
      String upper(String word) => word[0].toUpperCase() + word.substring(1);

      final rules = NormalizationRules(
        version: 1,
        apostrophes: const ['’', 'ʻ'],
        punctuation: '${ZzPack.punctuation.join()},«»',
        words: {
          "${w[0]}'${w[1]}": join([w[0], w[1]]),
        },
        endings: {"'${w[2]}": '$separator${w[3]}', w[2]: '$separator${w[5]}'},
        currency: {
          '¤': [w[6], w[7]],
        },
        spellings: {
          '${w[8]}${w[8]}': w[8],
          '${w[9]}-${w[10]}': '${w[9]}${w[10]}',
        },
        phrases: {
          join([w[11], w[12]]): join([w[13], w[12]]),
        },
        numbers: NumberWords(
          units: w.sublist(20, 40),
          tens: [null, null, ...w.sublist(40, 48)],
          hundred: w[48],
        ),
      );
      final normalizer = Normalizer(rules, separator: separator);
      String normalize(String text) => normalizer.normalize(text);

      test('keeps the words of plain sentences, lowercased', () {
        final plain = Normalizer(
          NormalizationRules(version: 1, punctuation: rules.punctuation),
          separator: separator,
        );
        for (final sentence in zz.ofKind(ItemKind.sentence)) {
          final text = sentence.text!;
          final words = text
              .substring(0, text.length - 1)
              .toLowerCase()
              .split(separator);
          expect(plain.normalize(text), join(words), reason: text);
        }
      });

      test('maps apostrophes, then expands whole words', () {
        expect(
          normalize('${upper(w[0])}’${w[1]}$separator${w[14]}!'),
          join([w[0], w[1], w[14]]),
        );
      });

      test('replaces the first ending that applies', () {
        expect(normalize("${w[15]}'${w[2]}"), join([w[15], w[3]]));
        expect(normalize('${w[15]}${w[2]}'), join([w[15], w[5]]));
        // An ending never takes the whole word.
        expect(normalize(w[2]), w[2]);
      });

      test('writes currency as its word for one or more', () {
        expect(normalize('¤30'), join([w[41], w[7]]));
        expect(normalize('¤1.'), join([w[21], w[6]]));
        expect(normalize('¤'), '¤');
      });

      test('respells, drops apostrophes and splits at hyphens', () {
        expect(normalize('${w[8]}${w[8]}'), w[8]);
        expect(normalize('${w[9]}-${w[10]}'), '${w[9]}${w[10]}');
        expect(normalize('${w[16]}-${w[17]}'), join([w[16], w[17]]));
        expect(normalize("${w[18]}'${w[19]}"), '${w[18]}${w[19]}');
      });

      test('replaces whole-word phrases only', () {
        expect(
          normalize(join([w[14], w[11], w[12]])),
          join([w[14], w[13], w[12]]),
        );
        final partial = join(['${w[11]}${w[11]}', w[12]]);
        expect(normalize(partial), partial);
      });

      test('writes 0–999 in words and leaves larger numbers', () {
        expect(normalize('7'), w[27]);
        expect(normalize('007'), w[27]);
        expect(normalize('19'), w[39]);
        expect(normalize('20'), w[40]);
        expect(normalize('35'), join([w[41], w[25]]));
        expect(normalize('300'), join([w[23], w[48]]));
        expect(normalize('305'), join([w[23], w[48], w[25]]));
        expect(normalize('999'), join([w[29], w[48], w[47], w[29]]));
        expect(normalize('1000'), '1000');
        expect(normalize('3x'), '3x');
      });

      test('keeps digits without number words', () {
        final bare = Normalizer(
          const NormalizationRules(version: 1),
          separator: separator,
        );
        expect(bare.normalize('35'), '35');
      });

      test('collapses whitespace and separators', () {
        expect(
          normalize(' ${w[0]}\t$separator$separator ${w[1]}\n'),
          join([w[0], w[1]]),
        );
        expect(normalize(' \t!'), '');
      });

      test('drops fillers and, when asked, words said twice', () {
        final hesitant = Normalizer(
          rules.copyWith(fillers: [w[50], w[51]], collapseRepeats: true),
          separator: separator,
        );
        expect(
          hesitant.normalize(
            '${upper(w[50])}, ${w[0]} ${w[0]} ${w[51]} ${w[1]}',
          ),
          join([w[0], w[1]]),
        );
        // A word may repeat after another one, and without the rule.
        expect(
          hesitant.normalize('${w[0]} ${w[1]} ${w[0]}'),
          join([w[0], w[1], w[0]]),
        );
        expect(normalize('${w[0]} ${w[0]}'), join([w[0], w[0]]));
        // Repeats are counted after numbers are written out: 7 7 → w[27].
        expect(hesitant.normalize('7 7'), w[27]);
      });

      test('reads its rules back from JSON in order', () {
        final back = NormalizationRules.fromJson(rules.toJson());
        expect(back, rules);
        expect(back.endings.keys, rules.endings.keys);
        expect(Normalizer(back, separator: separator).normalize('7'), w[27]);
      });
    });
  }

  group('Normalizer rejects', () {
    final zz = ZzPack.generate();
    final w = [for (final entry in zz.lexicon) entry.lemma];

    test('a separator that is not one character', () {
      const rules = NormalizationRules(version: 1);
      for (final separator in ['', '··']) {
        expect(
          () => Normalizer(rules, separator: separator),
          throwsArgumentError,
        );
      }
    });

    test('number words for a different range', () {
      final rules = NormalizationRules(
        version: 1,
        numbers: NumberWords(
          units: w.sublist(0, 19),
          tens: List.filled(10, null),
          hundred: w[20],
        ),
      );
      expect(() => Normalizer(rules), throwsArgumentError);
    });

    test('currency without a sign and two words', () {
      for (final currency in [
        {
          '¤': [w[0]],
        },
        {
          '¤¤': [w[0], w[1]],
        },
      ]) {
        expect(
          () => Normalizer(NormalizationRules(version: 1, currency: currency)),
          throwsArgumentError,
        );
      }
    });
  });
}
