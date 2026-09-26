import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

import 'zz_pack.dart';

void main() {
  final pack = ZzPack.generate();

  /// Lowercase surface tokens of a sentence text.
  List<String> tokensOf(ContentItem sentence, ZzPack pack) {
    var text = sentence.text!;
    for (final mark in ZzPack.punctuation) {
      if (text.endsWith(mark)) text = text.substring(0, text.length - 1);
    }
    return text.toLowerCase().split(pack.wordSeparator);
  }

  group('ZzPack.generate', () {
    test('is reproducible for the same seed', () {
      final again = ZzPack.generate();
      expect(again.lexicon, pack.lexicon);
      expect(again.forms, pack.forms);
      expect(again.items, pack.items);
      expect(again.links, pack.links);
    });

    test('differs for another seed', () {
      final other = ZzPack.generate(seed: 2);
      expect(
        other.lexicon.map((e) => e.lemma),
        isNot(pack.lexicon.map((e) => e.lemma)),
      );
    });

    test('ranks lemmas by frequency and spreads them over all levels', () {
      expect(
        pack.lexicon.map((e) => e.rank),
        List.generate(pack.lexicon.length, (i) => i + 1),
      );
      expect(pack.lexicon.map((e) => e.level).toSet(), CefrLevel.values);
      for (var i = 1; i < pack.lexicon.length; i++) {
        expect(
          pack.lexicon[i - 1].level.isAtMost(pack.lexicon[i].level),
          isTrue,
        );
      }
    });

    test('uses non-ASCII letters, so ASCII-only assumptions break', () {
      final nonAscii = RegExp('[^\u0000-\u007f]');
      expect(pack.lexicon.where((e) => nonAscii.hasMatch(e.lemma)), isNotEmpty);
    });

    test('has unique item keys and links between existing items', () {
      final keys = pack.items.map((i) => i.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
      for (final link in pack.links) {
        expect(keys, contains(link.from));
        expect(keys, contains(link.to));
      }
    });

    test('forms table maps every lemma to itself', () {
      for (final entry in pack.lexicon) {
        expect(pack.forms[entry.lemma], contains(entry.lemma));
      }
    });

    test('forms table has homographs and suppletive forms', () {
      final homographs = pack.forms.entries.where((f) => f.value.length > 1);
      expect(homographs, isNotEmpty);
      final suppletive = pack.forms.entries.where(
        (f) => f.value.every((lemma) => !f.key.startsWith(lemma)),
      );
      expect(suppletive, isNotEmpty);
    });

    test('sentence tokens lemmatize into the sentence lemma list', () {
      final lemmas = pack.lexicon.map((e) => e.lemma).toSet();
      for (final sentence in pack.ofKind(ItemKind.sentence)) {
        expect(lemmas, containsAll(sentence.lemmas));
        for (final token in tokensOf(sentence, pack)) {
          final candidates = pack.forms[token];
          expect(candidates, isNotNull, reason: '${sentence.key}: $token');
          expect(
            candidates!.any(sentence.lemmas.contains),
            isTrue,
            reason: '${sentence.key}: $token',
          );
        }
      }
    });

    test('sentences respect level discipline (i+1)', () {
      for (final sentence in pack.ofKind(ItemKind.sentence)) {
        final target = pack.item(sentence.targets.single);
        expect(sentence.level, target.level);
        for (final lemma in sentence.lemmas) {
          if (target.lemmas.contains(lemma)) continue;
          expect(
            pack.entry(lemma).level.isAtMost(sentence.level),
            isTrue,
            reason: '${sentence.key}: $lemma',
          );
        }
        for (final code in sentence.grammarCodes) {
          expect(pack.item(code).level.isAtMost(sentence.level), isTrue);
        }
      }
    });

    test('contrast links join senses of the same part of speech', () {
      final contrasts = pack.links.where(
        (l) => l.type == LinkType.contrastsWith,
      );
      expect(contrasts, isNotEmpty);
      for (final link in contrasts) {
        expect(link.from.split('.')[3], link.to.split('.')[3]);
      }
    });

    test('grammar codes are an ordered closed list', () {
      final codes = pack.grammarCodes;
      expect(codes, isNotEmpty);
      expect(codes.every((c) => c.startsWith('gp.${ZzPack.l2}.')), isTrue);
    });

    test('supports a word separator other than space', () {
      final dotted = ZzPack.generate(wordSeparator: '·');
      for (final sentence in dotted.ofKind(ItemKind.sentence)) {
        expect(sentence.text, isNot(contains(' ')));
        for (final token in tokensOf(sentence, dotted)) {
          expect(dotted.forms[token], isNotNull);
        }
      }
    });
  });
}
