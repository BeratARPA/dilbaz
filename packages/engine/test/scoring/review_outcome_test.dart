import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ReviewOutcome.rating (docs/03-activities.md §0.3)', () {
    // 25th percentile of 100–4000 ms: 1075 ms.
    final history = LatencyProfile.of([for (var i = 1; i <= 40; i++) i * 100]);

    ReviewRating recalled({required bool firstTry, required int latencyMs}) =>
        ReviewOutcome.recalled(
          firstTry: firstTry,
          latencyMs: latencyMs,
        ).rating(history);

    test('a first-try recall is Good, or Easy when fast', () {
      expect(recalled(firstTry: true, latencyMs: 1074), ReviewRating.easy);
      expect(recalled(firstTry: true, latencyMs: 1075), ReviewRating.good);
      expect(recalled(firstTry: true, latencyMs: 3000), ReviewRating.good);
    });

    test('Easy needs a history of latencies', () {
      const fast = ReviewOutcome.recalled(firstTry: true, latencyMs: 0);
      expect(fast.rating(LatencyProfile.none), ReviewRating.good);
    });

    test('right after the introduction a fast recall is only Good', () {
      const fast = ReviewOutcome.recalled(firstTry: true, latencyMs: 0);
      expect(fast.rating(history), ReviewRating.easy);
      expect(fast.rating(history, justIntroduced: true), ReviewRating.good);
      expect(
        const ReviewOutcome.notRecalled().rating(history, justIntroduced: true),
        ReviewRating.again,
      );
    });

    test('a later recall is Hard, however fast', () {
      expect(recalled(firstTry: false, latencyMs: 0), ReviewRating.hard);
    });

    test('neither a penalty nor inflation without the target or the LLM', () {
      expect(
        const ReviewOutcome.withoutTarget().rating(history),
        ReviewRating.hard,
      );
      expect(
        const ReviewOutcome.undecided().rating(history),
        ReviewRating.hard,
      );
    });

    test('no recall is Again', () {
      expect(
        const ReviewOutcome.notRecalled().rating(history),
        ReviewRating.again,
      );
    });

    test('only a recall is production evidence', () {
      expect(
        const ReviewOutcome.recalled(firstTry: false, latencyMs: 1).isEvidence,
        isTrue,
      );
      for (final outcome in const [
        ReviewOutcome.notRecalled(),
        ReviewOutcome.withoutTarget(),
        ReviewOutcome.undecided(),
      ]) {
        expect(outcome.isEvidence, isFalse, reason: '$outcome');
      }
    });
  });
}
