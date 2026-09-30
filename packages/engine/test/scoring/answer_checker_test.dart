import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

import '../fixtures/zz/zz_pack.dart';

/// A pack sentence as a card: its words and where its target is.
final class Card {
  new(this.sentence, this.key, this.words, this.target);

  final ContentItem sentence;
  final AnswerKey key;
  final List<String> words;

  /// Indices of the target words.
  final List<int> target;
}

void main() {
  for (final separator in [Normalizer.space, '·']) {
    group('AnswerChecker, words separated by "$separator"', () {
      final zz = ZzPack.generate(wordSeparator: separator);
      final language = PackLanguage(
        rules: NormalizationRules(
          version: 1,
          punctuation: ZzPack.punctuation.join(),
        ),
        forms: zz.forms,
        separator: separator,
      );
      final checker = AnswerChecker(language);
      String say(List<String> words) => '${words.join(separator)}.';

      Iterable<Card> cards(ItemKind kind) sync* {
        for (final sentence in zz.ofKind(ItemKind.sentence)) {
          final target = zz.item(sentence.targets.single);
          if (target.kind != kind) continue;
          final words = language.tokenize(sentence.text!);
          final hits = [
            for (final (i, word) in words.indexed)
              if (language.lemmasOf(word).any(target.lemmas.contains)) i,
          ];
          if (hits.length != target.lemmas.length ||
              words.length < 4 ||
              words.toSet().length != words.length) {
            continue;
          }
          yield Card(
            sentence,
            AnswerKey(
              reference: sentence.text!,
              targetLemmas: target.lemmas.toSet(),
              ruleCode: sentence.grammarCodes.firstOrNull,
            ),
            words,
            hits,
          );
        }
      }

      final senses = cards(ItemKind.wordSense).toList();
      final chunks = cards(ItemKind.chunk).toList();
      // Lemmas that have one form and are a form of nothing else.
      final spare = [
        for (final entry in zz.lexicon)
          if (zz.forms[entry.lemma]!.length == 1 &&
              zz.forms.values.where((l) => l.contains(entry.lemma)).length == 1)
            entry.lemma,
      ];
      List<String> unrelated(Card card, int count) => [
        for (final word in spare)
          if (!card.words.contains(word)) word,
      ].take(count).toList();

      test('has cards to check', () {
        expect(senses.length, greaterThan(20));
        expect(chunks, isNotEmpty);
      });

      group('match (step 2)', () {
        test('the reference, whatever the case and punctuation', () {
          for (final card in senses) {
            final loud = card.words.map((w) => w.toUpperCase()).toList();
            expect(
              checker.match('${loud.join(separator)}!', card.key),
              const Evaluation(verdict: Verdict.correct, targetOk: true),
            );
          }
        });

        test('a variant is correct, an alternative asks again', () {
          final card = senses.first;
          final variant = [...card.words.reversed];
          final alternative = [...card.words]
            ..[card.target.single] = unrelated(card, 1).single;
          final key = card.key.copyWith(
            variants: [say(variant)],
            alternatives: [say(alternative)],
          );
          expect(
            checker.match(say(variant), key),
            const Evaluation(verdict: Verdict.correct, targetOk: true),
          );
          expect(
            checker.match(say(alternative), key),
            const Evaluation(
              verdict: Verdict.acceptableVariant,
              targetOk: false,
            ),
          );
        });

        test('the card target decides, not the list an answer is in', () {
          // A sentence carries several items; its lists are written for
          // the ones it was chosen for.
          const correct = Evaluation(verdict: Verdict.correct, targetOk: true);
          const withoutTarget = Evaluation(
            verdict: Verdict.acceptableVariant,
            targetOk: false,
          );
          for (final card in senses.take(20)) {
            final withTarget = [...card.words.reversed];
            final without = [...card.words]
              ..[card.target.single] = unrelated(card, 1).single;
            final key = card.key.copyWith(
              variants: [say(without)],
              alternatives: [say(withTarget)],
            );
            expect(checker.match(say(without), key), withoutTarget);
            expect(checker.match(say(withTarget), key), correct);
          }
        });

        test('the lists decide when the target cannot be found', () {
          final card = senses.first;
          final variant = [...card.words.reversed];
          final alternative = [...card.words]
            ..[card.target.single] = unrelated(card, 1).single;
          for (final lemmas in [
            <String>{},
            {'${card.key.targetLemmas.single}q'},
          ]) {
            final key = card.key.copyWith(
              targetLemmas: lemmas,
              variants: [say(alternative)],
              alternatives: [say(variant)],
            );
            expect(
              checker.match(card.key.reference, key)!.verdict,
              Verdict.correct,
            );
            expect(
              checker.match(say(alternative), key)!.verdict,
              Verdict.correct,
            );
            expect(
              checker.match(say(variant), key),
              const Evaluation(
                verdict: Verdict.acceptableVariant,
                targetOk: false,
              ),
            );
          }
        });

        test('nothing heard is unintelligible', () {
          const unheard = Evaluation(
            verdict: Verdict.unintelligible,
            targetOk: false,
          );
          expect(checker.match('', senses.first.key), unheard);
          expect(checker.match(' ?! ', senses.first.key), unheard);
          expect(
            checker.checkWithoutLlm('.', senses.first.key),
            const AnswerCheck(evaluation: unheard),
          );
        });

        test('anything else waits for the LLM', () {
          final card = senses.first;
          expect(
            checker.match(say(card.words.skip(1).toList()), card.key),
            isNull,
          );
        });
      });

      group('listed answers by the card target', () {
        test('a word card keeps the answers that say its word', () {
          final card = senses.first;
          final t = card.target.single;
          final other = unrelated(card, 2);
          final withWord = [...card.words]..[t == 0 ? 1 : 0] = other[0];
          final withoutWord = [...card.words]..[t] = other[1];
          final key = card.key.copyWith(
            variants: [say(withWord), say(withoutWord)],
            alternatives: [say(card.words.reversed.toList())],
          );
          final lists = checker.listed(key);
          expect(lists.withTarget, [
            say(withWord),
            say(card.words.reversed.toList()),
          ]);
          expect(lists.withoutTarget, [say(withoutWord)]);
        });

        test('a grammar card keeps the answers that use its structure', () {
          final card = senses.first;
          final other = unrelated(card, 3);
          final [uses, lacks, alsoUses] = [
            for (final word in other) say([...card.words, word]),
          ];
          final key = card.key.copyWith(
            targetLemmas: {},
            ruleCode: 'gp.zz.target',
            variants: [uses, lacks],
            alternatives: [alsoUses],
            answerGrammar: {
              uses: ['gp.zz.target'],
              lacks: ['gp.zz.other'],
              alsoUses: ['gp.zz.other', 'gp.zz.target'],
            },
          );
          final lists = checker.listed(key);
          expect(lists.withTarget, [uses, alsoUses]);
          expect(lists.withoutTarget, [lacks]);
          expect(checker.match(alsoUses, key)!.verdict, Verdict.correct);
          expect(
            checker.match(lacks, key),
            const Evaluation(
              verdict: Verdict.acceptableVariant,
              targetOk: false,
            ),
          );
          // Without the codes of an answer, its list decides.
          final unknown = checker.listed(key.copyWith(answerGrammar: {}));
          expect(unknown.withTarget, [uses, lacks]);
          expect(unknown.withoutTarget, [alsoUses]);
        });
      });

      group('without the LLM (step 4)', () {
        test('an error outside the target is minor and recalls it', () {
          for (final card in senses) {
            final extra = card.target.single == 0 ? 1 : 0;
            final dropped = [...card.words]..removeAt(extra);
            expect(
              checker.checkWithoutLlm(say(dropped), card.key),
              const AnswerCheck(
                evaluation: Evaluation(
                  verdict: Verdict.minorError,
                  targetOk: true,
                ),
              ),
              reason: card.sentence.key,
            );
          }
        });

        test('two slips are small only in a long answer', () {
          List<String> twoDropped(Card card) {
            final others = [
              for (final (i, _) in card.words.indexed)
                if (i != card.target.single) i,
            ];
            return [
              for (final (i, word) in card.words.indexed)
                if (i != others[0] && i != others[1]) word,
            ];
          }

          final long = senses.firstWhere(
            (c) => c.words.length >= AnswerChecker.longAnswer,
          );
          expect(
            checker.checkWithoutLlm(say(twoDropped(long)), long.key).evaluation,
            const Evaluation(verdict: Verdict.minorError, targetOk: true),
          );
          final short = senses.firstWhere(
            (c) => c.words.length < AnswerChecker.longAnswer,
          );
          expect(
            checker
                .checkWithoutLlm(say(twoDropped(short)), short.key)
                .evaluation,
            const Evaluation(
              verdict: Verdict.uncertain,
              targetOk: true,
              llmPending: true,
            ),
          );
        });

        test('answers without the target are not aligned with', () {
          final card = senses.firstWhere((c) => c.target.single >= 1);
          final without = [...card.words]
            ..[card.target.single] = unrelated(card, 1).single;
          final key = card.key.copyWith(variants: [say(without)]);
          final answer = [...without]..removeAt(0);
          final check = checker.checkWithoutLlm(say(answer), key);
          // Against the reference the target is replaced; against the
          // listed answer only one word would be missing.
          expect(
            check.evaluation.verdict,
            isIn([Verdict.uncertain, Verdict.offTarget]),
          );
          expect(check.ladder?.answer, isNot(say(without)));
        });

        test('two swapped words outside the target are minor', () {
          final card = senses.firstWhere((c) => c.target.single >= 2);
          final swapped = [...card.words]
            ..[0] = card.words[1]
            ..[1] = card.words[0];
          expect(
            checker.checkWithoutLlm(say(swapped), card.key).evaluation,
            const Evaluation(verdict: Verdict.minorError, targetOk: true),
          );
        });

        test('the target in another form misses, with a form hint', () {
          var checked = 0;
          for (final card in senses) {
            final t = card.target.single;
            final lemma = card.key.targetLemmas.single;
            final other = zz.forms.entries
                .where(
                  (e) =>
                      e.key != card.words[t] &&
                      e.value.length == 1 &&
                      e.value.single == lemma,
                )
                .firstOrNull;
            if (other == null) continue;
            checked++;
            final answer = [...card.words]..[t] = other.key;
            expect(
              checker.checkWithoutLlm(say(answer), card.key),
              AnswerCheck(
                evaluation: const Evaluation(
                  verdict: Verdict.minorError,
                  targetOk: false,
                ),
                ladder: HintLadder(
                  kind: HintKind.wrongForm,
                  answer: card.key.reference,
                  place: HintPlace(
                    relation: HintRelation.at,
                    word: other.key,
                    index: t,
                  ),
                  ruleCode: card.key.ruleCode,
                ),
              ),
              reason: card.sentence.key,
            );
          }
          expect(checked, greaterThan(5));
        });

        test('a missing target misses; H2 names a word the learner said', () {
          for (final card in senses) {
            final t = card.target.single;
            final answer = [...card.words]..removeAt(t);
            final check = checker.checkWithoutLlm(say(answer), card.key);
            expect(
              check.evaluation,
              const Evaluation(verdict: Verdict.wrong, targetOk: false),
            );
            final ladder = check.ladder!;
            expect(ladder.kind, HintKind.missingWord);
            final place = ladder.place!;
            expect(answer[place.index], place.word);
            // I-02: nothing of the missing target in H1–H3.
            expect(place.word, isNot(card.words[t]));
            if (t < answer.length) {
              expect(place.relation, HintRelation.before);
              expect(place.index, t);
            } else {
              expect(place.relation, HintRelation.after);
              expect(place.index, t - 1);
            }
          }
        });

        test('another word in place of the target is left to the LLM', () {
          for (final card in senses) {
            final answer = [...card.words]
              ..[card.target.single] = unrelated(card, 1).single;
            expect(
              checker.checkWithoutLlm(say(answer), card.key),
              const AnswerCheck(
                evaluation: Evaluation(
                  verdict: Verdict.uncertain,
                  targetOk: false,
                  llmPending: true,
                ),
              ),
            );
          }
        });

        test('the target right but the rest far off is undecided', () {
          for (final card in senses) {
            final t = card.target.single;
            final fresh = unrelated(card, card.words.length);
            final answer = [
              for (final (i, word) in card.words.indexed)
                if (i == t) word else fresh[i],
            ];
            expect(
              checker.checkWithoutLlm(say(answer), card.key).evaluation,
              const Evaluation(
                verdict: Verdict.uncertain,
                targetOk: true,
                llmPending: true,
              ),
            );
          }
        });

        test(
          'without the target but mostly the same, it may be a paraphrase',
          () {
            var checked = 0;
            for (final card in senses.where((c) => c.words.length >= 4)) {
              final t = card.target.single;
              // Two words for the target: too big a change to be small.
              final answer = [
                for (final (i, word) in card.words.indexed)
                  if (i == t) ...unrelated(card, 2) else word,
              ];
              expect(
                checker.checkWithoutLlm(say(answer), card.key),
                const AnswerCheck(
                  evaluation: Evaluation(
                    verdict: Verdict.uncertain,
                    targetOk: false,
                    llmPending: true,
                  ),
                ),
                reason: card.sentence.key,
              );
              checked++;
            }
            expect(checked, greaterThan(5));
          },
        );

        test('no target and little in common is off target', () {
          for (final card in senses) {
            final answer = unrelated(card, card.words.length);
            final check = checker.checkWithoutLlm(say(answer), card.key);
            expect(
              check,
              AnswerCheck(
                evaluation: const Evaluation(
                  verdict: Verdict.offTarget,
                  targetOk: false,
                ),
                ladder: HintLadder(
                  kind: HintKind.meaning,
                  answer: card.key.reference,
                  ruleCode: card.key.ruleCode,
                ),
              ),
            );
          }
        });

        test('a fragment without the target is off target too', () {
          final card = senses.firstWhere((c) => c.words.length >= 5);
          final t = card.target.single;
          final others = [
            for (final (i, word) in card.words.indexed)
              if (i != t) word,
          ];
          final fragment = others.take(others.length - 2).toList();
          expect(
            checker.checkWithoutLlm(say(fragment), card.key).evaluation,
            const Evaluation(verdict: Verdict.offTarget, targetOk: false),
          );
        });

        test('the target out of place misses, with an order hint', () {
          final card = senses.firstWhere((c) => c.target.single >= 1);
          final t = card.target.single;
          final answer = [...card.words]
            ..[t - 1] = card.words[t]
            ..[t] = card.words[t - 1];
          final check = checker.checkWithoutLlm(say(answer), card.key);
          expect(
            check.evaluation,
            const Evaluation(verdict: Verdict.wrong, targetOk: false),
          );
          expect(check.ladder!.kind, HintKind.wordOrder);
          expect(
            check.ladder!.place,
            HintPlace(
              relation: HintRelation.at,
              word: card.words[t],
              index: t - 1,
            ),
          );
        });

        test('a word pushed into a chunk breaks the target', () {
          for (final card in chunks) {
            final inside = card.target.last;
            final extra = unrelated(card, 1).single;
            final answer = [...card.words]..insert(inside, extra);
            final check = checker.checkWithoutLlm(say(answer), card.key);
            expect(
              check.evaluation,
              const Evaluation(verdict: Verdict.wrong, targetOk: false),
            );
            expect(check.ladder!.kind, HintKind.extraWord);
            expect(
              check.ladder!.place,
              HintPlace(relation: HintRelation.at, word: extra, index: inside),
            );
          }
        });

        test('the hints follow the nearest correct answer', () {
          final card = senses.firstWhere((c) => c.target.single >= 2);
          final variant = [...card.words]
            ..[0] = card.words[1]
            ..[1] = card.words[0];
          final key = card.key.copyWith(variants: [say(variant)]);
          final answer = [...variant]..removeAt(card.target.single);
          final check = checker.checkWithoutLlm(say(answer), key);
          expect(check.evaluation.verdict, Verdict.wrong);
          expect(check.ladder!.answer, say(variant));
        });

        test('with no target word known, the whole answer is the target', () {
          final card = senses.first;
          final key = card.key.copyWith(targetLemmas: {});
          final extra = card.target.single == 0 ? 1 : 0;
          final dropped = [...card.words]..removeAt(extra);
          expect(
            checker.checkWithoutLlm(say(dropped), key).evaluation,
            const Evaluation(verdict: Verdict.wrong, targetOk: false),
          );
        });

        test('a missing last word is placed after the word before it', () {
          final card = senses.first;
          final targetWord = card.words[card.target.single];
          final others = [...card.words]..remove(targetWord);
          final key = card.key.copyWith(
            reference: say([...others, targetWord]),
          );
          final check = checker.checkWithoutLlm(say(others), key);
          expect(
            check.ladder!.place,
            HintPlace(
              relation: HintRelation.after,
              word: others.last,
              index: others.length - 1,
            ),
          );
        });
      });

      test('checks drive a card review without the LLM', () {
        final card = senses.first;
        final t = card.target.single;
        final synonym = [...card.words]..[t] = unrelated(card, 1).single;
        final key = card.key.copyWith(alternatives: [say(synonym)]);
        CardReview next(CardReview review, List<String> said) => review.answer(
          checker.checkWithoutLlm(say(said), key).evaluation,
          latencyMs: 1500,
        );

        // A correct answer without the target: asked again, nothing used.
        var review = next(const CardReview(), synonym);
        expect(review.reprompted, isTrue);
        expect(review.misses, 0);
        // Then the target is left out: a miss, and the first hint opens.
        review = next(review, [...card.words]..removeAt(t));
        expect(review.misses, 1);
        expect(review.hintLevel, 1);
        // Nothing heard: not counted.
        review = review.answer(
          checker.checkWithoutLlm('?', key).evaluation,
          latencyMs: 900,
        );
        expect(review.misses, 1);
        // The reference at last: recalled, but not on the first try.
        review = next(review, card.words);
        expect(
          review.outcome,
          const ReviewOutcome.recalled(firstTry: false, latencyMs: 1500),
        );
        expect(review.outcome!.rating(LatencyProfile.none), ReviewRating.hard);
      });
    });
  }
}
