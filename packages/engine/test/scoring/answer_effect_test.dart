import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

AnswerEffect effect(
  Verdict verdict, {
  bool targetOk = true,
  bool llmPending = false,
}) => AnswerEffect.of(
  Evaluation(verdict: verdict, targetOk: targetOk, llmPending: llmPending),
);

void main() {
  group('AnswerEffect.of (docs/03-activities.md §0.2)', () {
    test('a correct answer with the target recalls it', () {
      expect(effect(Verdict.correct), AnswerEffect.recalled);
      expect(effect(Verdict.acceptableVariant), AnswerEffect.recalled);
    });

    test('a correct answer without the target is asked again', () {
      expect(
        effect(Verdict.acceptableVariant, targetOk: false),
        AnswerEffect.correctWithoutTarget,
      );
      expect(
        effect(Verdict.correct, targetOk: false),
        AnswerEffect.correctWithoutTarget,
      );
    });

    test('a minor error misses only when it touches the target', () {
      expect(effect(Verdict.minorError), AnswerEffect.recalled);
      expect(effect(Verdict.minorError, targetOk: false), AnswerEffect.missed);
    });

    test('wrong and off-target answers miss', () {
      for (final targetOk in [true, false]) {
        for (final verdict in [Verdict.wrong, Verdict.offTarget]) {
          expect(effect(verdict, targetOk: targetOk), AnswerEffect.missed);
        }
      }
    });

    test('an unintelligible answer is not counted', () {
      for (final targetOk in [true, false]) {
        expect(
          effect(Verdict.unintelligible, targetOk: targetOk),
          AnswerEffect.unintelligible,
        );
      }
    });

    test('uncertain without the LLM stays undecided', () {
      for (final targetOk in [true, false]) {
        expect(
          effect(Verdict.uncertain, targetOk: targetOk, llmPending: true),
          AnswerEffect.undecided,
        );
      }
    });

    test('uncertain after asking the learner counts as correct', () {
      expect(effect(Verdict.uncertain), AnswerEffect.recalled);
    });

    test('only an uncertain verdict can wait for the LLM', () {
      expect(effect(Verdict.correct, llmPending: true), AnswerEffect.recalled);
      expect(effect(Verdict.wrong, llmPending: true), AnswerEffect.missed);
    });

    test('verdict codes are those of attempts.verdict and answer_check', () {
      expect(Verdict.values.map((v) => v.code), [
        'correct',
        'acceptable_variant',
        'minor_error',
        'wrong',
        'off_target',
        'unintelligible',
        'uncertain',
      ]);
    });
  });
}
