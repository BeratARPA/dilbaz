import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

final LanguageServices zz = PackLanguage(
  rules: const NormalizationRules(version: 1, fillers: ['eh']),
  forms: {
    'bada': {'bada'},
    'badan': {'bada'},
    'kolu': {'kolu'},
    'sima': {'sima'},
    'dero': {'dero'},
  },
);

List<TimedWord> say(String text) => [
  for (final (i, word) in text.split(' ').indexed)
    TimedWord(text: word, startMs: i * 500, endMs: i * 500 + 400),
];

const List<UsableItem> items = [
  (key: 'zz.ws.bada', kind: ItemKind.wordSense, lemmas: ['bada']),
  (key: 'zz.ws.dero', kind: ItemKind.wordSense, lemmas: ['dero']),
  (key: 'zz.chunk.sima_kolu', kind: ItemKind.chunk, lemmas: ['sima', 'kolu']),
  (key: 'zz.sent.1', kind: ItemKind.sentence, lemmas: ['bada', 'kolu']),
];

void main() {
  group('free use (docs/04 §3)', () {
    test(
      'words by lemma, chunks in order; errors and sentences do not count',
      () {
        final used = usedWithoutError(
          say('badan sima eh kolu dero'),
          annotation: const SpeechAnnotation(
            taskOutcome: TaskOutcome.done,
            errors: [
              SpeechError(
                startI: 4,
                endI: 4,
                tag: 'zz.form',
                correction: 'deru',
                severity: 1,
              ),
            ],
          ),
          items: items,
          language: zz,
        );
        // "eh" between "sima" and "kolu" is skipped; "dero" carries an error.
        expect(used, {'zz.ws.bada', 'zz.chunk.sima_kolu'});
      },
    );

    test('a chunk in another order, or broken by an error, is not used', () {
      final used = usedWithoutError(
        say('kolu sima bada kolu'),
        annotation: const SpeechAnnotation(
          taskOutcome: TaskOutcome.partial,
          errors: [
            SpeechError(
              startI: 0,
              endI: 0,
              tag: 'zz.form',
              correction: 'kolu',
              severity: 1,
            ),
          ],
          fillers: [SpokenFiller(i: 3, kind: FillerKind.l1)],
        ),
        items: items,
        language: zz,
      );
      expect(used, {'zz.ws.bada'});
      expect(
        usedWithoutError(
          const [],
          annotation: const SpeechAnnotation(taskOutcome: TaskOutcome.notDone),
          items: items,
          language: zz,
        ),
        isEmpty,
      );
    });
  });

  group('the counts of the Progress tab', () {
    final now = DateTime.utc(2026, 10);

    ItemEvidence evidence(CardMode mode, {required int stabilityDays}) {
      final stability = stabilityDays.toDouble();
      return ItemEvidence([
        CardRecord(
          mode: mode,
          memory: CardMemory(
            fsrsCardId: 1,
            state: MemoryState.review,
            due: now.add(const Duration(days: 3)),
            stability: stability,
            difficulty: 5,
            lastReview: now.subtract(const Duration(days: 1)),
          ),
          reviews: [
            ReviewRecord(
              at: now.subtract(const Duration(days: 1)),
              rating: ReviewRating.good,
              evidence: true,
              stability: stability,
            ),
          ],
        ),
      ]);
    }

    test('known, recallable, durable and used are counted', () {
      final counts = countEvidence(
        {
          'a': evidence(CardMode.speak, stabilityDays: 3),
          'b': evidence(CardMode.speak, stabilityDays: 10),
          'c': evidence(CardMode.speak, stabilityDays: 10),
          'd': evidence(CardMode.recognizeAudio, stabilityDays: 10),
        },
        now: now,
        freeUseDays: {'a': 5, 'b': 2, 'c': 1},
      );
      // "a" is learning: free use alone does not make it used.
      expect(counts, (known: 3, recallable: 2, durable: 0, used: 1));
    });

    test('transfer needs a recallable item and two days', () {
      expect(withTransfer(ItemLevel.learning, 9), ItemLevel.learning);
      expect(withTransfer(ItemLevel.recallable, 1), ItemLevel.recallable);
      expect(withTransfer(ItemLevel.durable, 2), ItemLevel.transferred);
    });
  });
}
