import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

const right = Evaluation(verdict: Verdict.correct, targetOk: true);
const wrong = Evaluation(verdict: Verdict.wrong, targetOk: false);
const synonym = Evaluation(verdict: Verdict.acceptableVariant, targetOk: false);
const unheard = Evaluation(verdict: Verdict.unintelligible, targetOk: false);
const pending = Evaluation(
  verdict: Verdict.uncertain,
  targetOk: true,
  llmPending: true,
);

extension on CardReview {
  CardReview say(Evaluation evaluation) => answer(evaluation, latencyMs: 2000);

  ReviewRating get rated => outcome!.rating(LatencyProfile.none);
}

void main() {
  group('CardReview (docs/03-activities.md §0.2–0.3)', () {
    test('starts with no answer, no miss and no hint', () {
      const review = CardReview();
      expect(review.maxAttempts, CardReview.defaultMaxAttempts);
      expect(review.misses, 0);
      expect(review.hintLevel, 0);
      expect(review.reprompted, isFalse);
      expect(review.lastEffect, isNull);
      expect(review.isDone, isFalse);
    });

    test('a first-try recall is Good and evidence', () {
      final review = const CardReview().say(right);
      expect(review.isDone, isTrue);
      expect(
        review.outcome,
        const ReviewOutcome.recalled(firstTry: true, latencyMs: 2000),
      );
      expect(review.rated, ReviewRating.good);
      expect(review.outcome!.isEvidence, isTrue);
    });

    test('each miss uses up an attempt and opens the next hint', () {
      final first = const CardReview().say(wrong);
      expect(first.isDone, isFalse);
      expect(first.misses, 1);
      expect(first.hintLevel, 1);
      expect(first.lastEffect, AnswerEffect.missed);
      final second = first.say(wrong);
      expect(second.misses, 2);
      expect(second.hintLevel, 2);
    });

    test('wrong, H1, wrong, H2, correct is Hard with evidence', () {
      final review = const CardReview().say(wrong).say(wrong).say(right);
      expect(
        review.outcome,
        const ReviewOutcome.recalled(firstTry: false, latencyMs: 2000),
      );
      expect(review.rated, ReviewRating.hard);
      expect(review.outcome!.isEvidence, isTrue);
    });

    test('three misses end the review as Again', () {
      final review = const CardReview().say(wrong).say(wrong).say(wrong);
      expect(review.outcome, const ReviewOutcome.notRecalled());
      expect(review.misses, 3);
      expect(review.hintLevel, 2);
      expect(review.rated, ReviewRating.again);
      expect(review.outcome!.isEvidence, isFalse);
    });

    test('the attempt limit can be lower', () {
      final review = const CardReview(maxAttempts: 2).say(wrong).say(wrong);
      expect(review.outcome, const ReviewOutcome.notRecalled());
    });

    group('hints', () {
      test('open one by one after a miss; H4 ends the review as Again', () {
        var review = const CardReview().say(wrong).nextHint();
        expect(review.hintLevel, 2);
        review = review.nextHint();
        expect(review.hintLevel, 3);
        expect(review.isDone, isFalse);
        review = review.nextHint();
        expect(review.hintLevel, CardReview.answerLevel);
        expect(review.rated, ReviewRating.again);
      });

      test('a miss after H3 opens the answer', () {
        final review = const CardReview()
            .say(wrong)
            .nextHint()
            .nextHint()
            .say(wrong);
        expect(review.misses, 2);
        expect(review.hintLevel, CardReview.answerLevel);
        expect(review.rated, ReviewRating.again);
      });

      test('a recall after a requested hint is Hard', () {
        final review = const CardReview().say(wrong).nextHint().say(right);
        expect(review.rated, ReviewRating.hard);
      });

      test('there is no hint before a miss (I-02)', () {
        expect(() => const CardReview().nextHint(), throwsStateError);
        expect(
          () => const CardReview().say(synonym).nextHint(),
          throwsStateError,
        );
      });

      test('the answer is not shown before a try (I-01)', () {
        expect(() => const CardReview().reveal(), throwsStateError);
        expect(
          () => const CardReview().say(unheard).reveal(),
          throwsStateError,
        );
      });

      test('showing the answer after a miss is Again', () {
        final review = const CardReview().say(wrong).reveal();
        expect(review.hintLevel, CardReview.answerLevel);
        expect(review.rated, ReviewRating.again);
      });
    });

    group('a correct answer without the target', () {
      test('is asked again without using up an attempt or a hint', () {
        final review = const CardReview().say(synonym);
        expect(review.isDone, isFalse);
        expect(review.reprompted, isTrue);
        expect(review.misses, 0);
        expect(review.hintLevel, 0);
        expect(review.lastEffect, AnswerEffect.correctWithoutTarget);
      });

      test('then the target is Hard, with evidence', () {
        final review = const CardReview().say(synonym).say(right);
        expect(
          review.outcome,
          const ReviewOutcome.recalled(firstTry: false, latencyMs: 2000),
        );
        expect(review.rated, ReviewRating.hard);
        expect(review.outcome!.isEvidence, isTrue);
      });

      test('twice is Hard, without evidence', () {
        final review = const CardReview().say(synonym).say(synonym);
        expect(review.outcome, const ReviewOutcome.withoutTarget());
        expect(review.rated, ReviewRating.hard);
        expect(review.outcome!.isEvidence, isFalse);
      });

      test('then showing the target is Hard, without evidence', () {
        final review = const CardReview().say(synonym).reveal();
        expect(review.outcome, const ReviewOutcome.withoutTarget());
        expect(review.rated, ReviewRating.hard);
      });

      test('after a miss, showing the target is Again', () {
        final review = const CardReview().say(wrong).say(synonym).reveal();
        expect(review.rated, ReviewRating.again);
      });

      test('leaves the attempts for misses', () {
        final review = const CardReview().say(wrong).say(wrong).say(synonym);
        expect(review.isDone, isFalse);
        expect(review.misses, 2);
        expect(review.say(wrong).rated, ReviewRating.again);
      });
    });

    test('an unintelligible answer is not counted', () {
      final start = const CardReview().say(wrong);
      final review = start.say(unheard).say(unheard);
      expect(review, start.copyWith(lastEffect: AnswerEffect.unintelligible));
    });

    test('undecided without the LLM is always Hard, without evidence', () {
      for (final start in [
        const CardReview(),
        const CardReview().say(wrong).say(wrong),
      ]) {
        final review = start.say(pending);
        expect(review.outcome, const ReviewOutcome.undecided());
        expect(review.rated, ReviewRating.hard);
        expect(review.outcome!.isEvidence, isFalse);
      }
    });

    test('a finished review takes no more steps', () {
      final done = const CardReview().say(wrong).say(right);
      expect(() => done.say(right), throwsStateError);
      expect(done.nextHint, throwsStateError);
      expect(done.reveal, throwsStateError);
    });

    test('rejects a negative latency', () {
      expect(
        () => const CardReview().answer(right, latencyMs: -1),
        throwsArgumentError,
      );
    });
  });

  test('a review rates the card; the state after it is stored', () {
    final shown = DateTime.utc(2026, 9, 30, 8);
    final at = shown.add(const Duration(seconds: 40));
    final scheduler = SrsScheduler(SrsConfig.replay);
    final card = scheduler.newCard(fsrsCardId: 1, now: shown);

    final review = const CardReview().say(wrong).say(wrong).say(right);
    final after = scheduler.review(card, review.rated, at: at);

    expect(after, scheduler.review(card, ReviewRating.hard, at: at));
    expect(after.reps, 1);
    expect(CardMemory.fromJson(after.toJson()), after);
  });
}
