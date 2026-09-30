import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

import '../fixtures/zz/zz_pack.dart';

void main() {
  final zz = ZzPack.generate();
  // Spread the 400 synthetic lemmas over five bands of a thousand.
  final ranks = {for (final entry in zz.lexicon) entry.lemma: entry.rank * 12};
  String lemmaOfBand(int band) =>
      ranks.entries.firstWhere((e) => XlexResult.bandOf(e.value) == band).key;
  const xlex = XlexResult(
    score: 2100,
    bandRates: {1: 1.0, 2: 0.8, 3: 0.5, 4: 0.2, 5: 0.1},
    falseAlarmRate: 0.1,
  );

  group('LemmaKnowledge (docs/06-assessment.md §2, I-06)', () {
    test('a lemma known through cards is known', () {
      final rare = lemmaOfBand(5);
      final knowledge = LemmaKnowledge(known: {rare}, ranks: ranks, xlex: xlex);
      expect(knowledge.probability(rare), 1);
    });

    test('any other lemma has the probability of its band', () {
      final knowledge = LemmaKnowledge(
        known: const {},
        ranks: ranks,
        xlex: xlex,
      );
      expect(knowledge.probability(lemmaOfBand(1)), closeTo(0.9, 1e-9));
      expect(knowledge.probability(lemmaOfBand(3)), closeTo(0.4, 1e-9));
      expect(knowledge.probability(lemmaOfBand(5)), 0);
    });

    test('a lemma outside the lexicon is unknown', () {
      final knowledge = LemmaKnowledge(
        known: const {},
        ranks: ranks,
        xlex: xlex,
      );
      expect(knowledge.probability('${lemmaOfBand(1)}q'), 0);
    });

    test('before any test only cards count', () {
      final common = lemmaOfBand(1);
      final knowledge = LemmaKnowledge(known: {common}, ranks: ranks);
      expect(knowledge.probability(common), 1);
      expect(knowledge.probability(lemmaOfBand(2)), 0);
    });

    test('coverage is the mean probability of the lemmas of a text', () {
      final a = lemmaOfBand(1);
      final b = lemmaOfBand(3);
      final c = lemmaOfBand(5);
      final knowledge = LemmaKnowledge(known: {c}, ranks: ranks, xlex: xlex);
      expect(knowledge.coverage([a, b, c]), closeTo((0.9 + 0.4 + 1) / 3, 1e-9));
      // A repeated word weighs as often as it occurs.
      expect(
        knowledge.coverage([a, a, b]),
        closeTo((0.9 + 0.9 + 0.4) / 3, 1e-9),
      );
      expect(knowledge.coverage(const []), 1);
    });

    test('grows with cards, sentence by sentence', () {
      for (final sentence in zz.ofKind(ItemKind.sentence).take(30)) {
        final before = LemmaKnowledge(
          known: const {},
          ranks: ranks,
          xlex: xlex,
        );
        final after = LemmaKnowledge(
          known: sentence.lemmas.toSet(),
          ranks: ranks,
          xlex: xlex,
        );
        expect(after.coverage(sentence.lemmas), 1);
        expect(
          before.coverage(sentence.lemmas),
          lessThanOrEqualTo(after.coverage(sentence.lemmas)),
        );
      }
    });

    test('cards make a lemma known through its word senses', () {
      final t0 = DateTime.utc(2026, 1, 1, 8);
      final scheduler = SrsScheduler(SrsConfig.replay);
      // Two recalls on day 0 and one on day 3: recallable.
      CardRecord recalled(CardMode mode) {
        var memory = scheduler.newCard(fsrsCardId: 1, now: t0);
        final reviews = <ReviewRecord>[];
        for (final minutes in [0, 10, 3 * 1440]) {
          final at = t0.add(Duration(minutes: minutes));
          memory = scheduler.review(memory, ReviewRating.good, at: at);
          reviews.add(
            ReviewRecord(
              at: at,
              rating: ReviewRating.good,
              evidence: true,
              stability: memory.stability!,
            ),
          );
        }
        return CardRecord(mode: mode, memory: memory, reviews: reviews);
      }

      // Four senses of four different lemmas.
      final senses = <ContentItem>[];
      for (final sense in zz.ofKind(ItemKind.wordSense)) {
        if (senses.every((s) => s.lemmas.single != sense.lemmas.single)) {
          senses.add(sense);
        }
      }
      final chunk = zz.ofKind(ItemKind.chunk).first;
      final [spoken, heard, started, untouched] = senses.take(4).toList();
      final knowledge = LemmaKnowledge.fromCards(
        items: zz.items,
        evidence: {
          spoken.key: ItemEvidence([recalled(CardMode.speak)]),
          heard.key: ItemEvidence([recalled(CardMode.recognizeAudio)]),
          started.key: ItemEvidence([
            CardRecord(
              mode: CardMode.speak,
              memory: scheduler.newCard(fsrsCardId: 2, now: t0),
            ),
          ]),
          chunk.key: ItemEvidence([recalled(CardMode.speak)]),
        },
        ranks: ranks,
      );
      // Produced or recognized word senses; not a card just started, and
      // not the words of a known chunk.
      expect(knowledge.known, {...spoken.lemmas, ...heard.lemmas});
      expect(knowledge.probability(spoken.lemmas.single), 1);
      expect(knowledge.probability(started.lemmas.single), 0);
      expect(knowledge.probability(untouched.lemmas.single), 0);
    });
  });
}
