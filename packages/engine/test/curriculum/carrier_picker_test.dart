import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

import '../fixtures/zz/zz_pack.dart';

void main() {
  final zz = ZzPack.generate();
  final sentences = zz.ofKind(ItemKind.sentence);
  final ranks = {for (final entry in zz.lexicon) entry.lemma: entry.rank};
  const picker = CarrierPicker();

  // A word sense carried by at least two sentences.
  final target = zz
      .ofKind(ItemKind.wordSense)
      .firstWhere(
        (sense) =>
            sentences.where((s) => s.targets.contains(sense.key)).length >= 2,
      );
  final carriers = [
    for (final sentence in sentences)
      if (sentence.targets.contains(target.key)) sentence,
  ];
  Set<String> othersOf(ContentItem sentence) =>
      sentence.lemmas.toSet().difference(target.lemmas.toSet());

  group('CarrierPicker (docs/02-curriculum.md §4.4)', () {
    test('counts the other lemmas the learner does not know', () {
      final nothing = LemmaKnowledge(known: const {}, ranks: ranks);
      final choices = picker.pick(
        target: target,
        candidates: sentences,
        knowledge: nothing,
      );
      expect(choices.map((c) => c.carrier).toSet(), carriers.toSet());
      for (final choice in choices) {
        expect(choice.unknown, othersOf(choice.carrier).length);
        expect(choice.fits, isFalse);
      }
      // Fewest unknown first.
      final unknown = [for (final choice in choices) choice.unknown];
      expect(unknown, [...unknown]..sort());
    });

    test('a carrier fits when its other words are known (i+1)', () {
      final carrier = carriers.last;
      final choices = picker.pick(
        target: target,
        candidates: sentences,
        knowledge: LemmaKnowledge(known: othersOf(carrier), ranks: ranks),
      );
      // The target itself does not have to be known.
      expect(choices.first.unknown, 0);
      expect(choices.first.fits, isTrue);
      expect(
        othersOf(choices.first.carrier).difference(othersOf(carrier)),
        isEmpty,
      );
    });

    test('lemmas likely known from the vocabulary test count in part', () {
      const xlex = XlexResult(
        score: 900,
        bandRates: {1: 0.9},
        falseAlarmRate: 0,
      );
      final choices = picker.pick(
        target: target,
        candidates: carriers,
        knowledge: LemmaKnowledge(known: const {}, ranks: ranks, xlex: xlex),
      );
      for (final choice in choices) {
        final others = othersOf(choice.carrier).length;
        expect(choice.unknown, closeTo(others * 0.1, 1e-9));
        expect(choice.fits, others <= 5);
      }
    });

    test(
      'equally known carriers: the shorter, then the easier, comes first',
      () {
        ContentItem sentence(String key, int words, CefrLevel level) =>
            ContentItem(
              key: key,
              kind: ItemKind.sentence,
              level: level,
              lemmas: [
                ...target.lemmas,
                for (var i = 0; i < words; i++) zz.lexicon[i].lemma,
              ],
              targets: [target.key],
            );
        final known = LemmaKnowledge(
          known: {for (final entry in zz.lexicon.take(10)) entry.lemma},
          ranks: ranks,
        );
        final choices = picker.pick(
          target: target,
          candidates: [
            sentence('zz.sent.long', 5, CefrLevel.a1),
            sentence('zz.sent.hard', 3, CefrLevel.a2),
            sentence('zz.sent.b', 3, CefrLevel.a1),
            sentence('zz.sent.a', 3, CefrLevel.a1),
          ],
          knowledge: known,
        );
        expect(choices.map((c) => c.carrier.key), [
          'zz.sent.a',
          'zz.sent.b',
          'zz.sent.hard',
          'zz.sent.long',
        ]);
      },
    );

    test('takes only sentences that carry the target', () {
      final other = sentences.firstWhere(
        (s) => !s.targets.contains(target.key),
      );
      final removed = carriers.first.copyWith(deprecated: true);
      final choices = picker.pick(
        target: target,
        candidates: [other, removed, target, ...carriers.skip(1)],
        knowledge: LemmaKnowledge(known: const {}, ranks: ranks),
      );
      expect(choices.map((c) => c.carrier), isNot(contains(other)));
      expect(choices.map((c) => c.carrier), isNot(contains(removed)));
      expect(choices, hasLength(carriers.length - 1));
    });

    test('a chunk without a sentence carries itself; a word does not', () {
      final chunk = zz.ofKind(ItemKind.chunk).first;
      final nothing = LemmaKnowledge(known: const {}, ranks: ranks);
      expect(
        picker.pick(target: chunk, candidates: const [], knowledge: nothing),
        [CarrierChoice(carrier: chunk, unknown: 0, fits: true)],
      );
      expect(
        picker.pick(target: target, candidates: const [], knowledge: nothing),
        isEmpty,
      );
    });
  });
}
