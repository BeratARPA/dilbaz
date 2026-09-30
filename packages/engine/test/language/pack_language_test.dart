import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

import '../fixtures/zz/zz_pack.dart';

void main() {
  for (final separator in [Normalizer.space, '·']) {
    group('PackLanguage, words separated by "$separator"', () {
      final zz = ZzPack.generate(wordSeparator: separator);
      final LanguageServices language = PackLanguage(
        rules: NormalizationRules(
          version: 1,
          punctuation: ZzPack.punctuation.join(),
        ),
        forms: zz.forms,
        separator: separator,
      );

      test('tokenizes the normalized text', () {
        final sentence = zz.ofKind(ItemKind.sentence).first;
        final tokens = language.tokenize(sentence.text!);
        expect(tokens.join(separator), language.normalize(sentence.text!));
        expect(tokens, isNot(contains(separator)));
      });

      test('finds every lemma of a sentence through the forms table', () {
        for (final sentence in zz.ofKind(ItemKind.sentence)) {
          final found = {
            for (final token in language.tokenize(sentence.text!))
              ...language.lemmasOf(token),
          };
          expect(found, containsAll(sentence.lemmas), reason: sentence.key);
        }
      });

      test('gives homographs every lemma, unknown tokens themselves', () {
        final homograph = zz.forms.entries.firstWhere(
          (e) => e.value.length > 1,
        );
        expect(language.lemmasOf(homograph.key), homograph.value);
        expect(language.lemmasOf('${homograph.key}q'), {'${homograph.key}q'});
      });

      test('knows the forms of the pack and no others', () {
        final form = zz.forms.keys.first;
        expect(language.knows(form), isTrue);
        expect(language.knows('${form}q'), isFalse);
      });
    });
  }
}
