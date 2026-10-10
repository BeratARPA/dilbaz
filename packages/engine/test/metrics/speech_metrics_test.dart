import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

/// A synthetic language: "eh" and "mm" are its hesitation sounds.
final LanguageServices zz = PackLanguage(
  rules: const NormalizationRules(
    version: 1,
    punctuation: '.,?!',
    fillers: ['eh', 'mm'],
  ),
  forms: {
    'bada': {'bada'},
    'badan': {'bada'},
    'kolu': {'kolu'},
    'sima': {'sima'},
    'dero': {'dero'},
  },
);

TimedWord word(String text, int startMs, int endMs) =>
    TimedWord(text: text, startMs: startMs, endMs: endMs);

/// Six words over 3.9 s: a 400 ms pause after "kolu" and a 1.2 s one after
/// "sima"; "eh" hesitates.
final List<TimedWord> recording = [
  word('bada', 0, 400),
  word('kolu', 450, 800),
  word('eh', 1200, 1400),
  word('sima', 1450, 1800),
  word('dero', 3000, 3400),
  word('kolu', 3500, 3900),
];

const double minutes = 3900 / 60000;

void main() {
  group('fluency from word times (docs/06 §3.3)', () {
    final metrics = SpeechMetrics.of(recording, language: zz)!;

    test('speaking time leaves out the silence around the words', () {
      final padded = [
        for (final w in recording)
          w.copyWith(startMs: w.startMs + 2000, endMs: w.endMs + 2000),
      ];
      expect(metrics.speakingMs, 3900);
      expect(SpeechMetrics.of(padded, language: zz), metrics);
    });

    test('words are what was said without hesitation', () {
      expect(metrics.words, 5);
      expect(metrics.speechRate, closeTo(5 / minutes, 1e-9));
      expect(metrics.filledPausesPerMin, closeTo(1 / minutes, 1e-9));
    });

    test('pauses of 250 ms and more; long ones from a second', () {
      // 3.9 s less the two pauses of 0.4 s and 1.2 s.
      expect(metrics.articulationRate, closeTo(5 / (2300 / 60000), 1e-9));
      expect(metrics.longPausesPerMin, closeTo(1 / minutes, 1e-9));
      // Runs: bada kolu | (eh) sima | dero kolu.
      expect(metrics.meanLengthOfRun, closeTo(5 / 3, 1e-9));
    });

    test('without an annotation, what needs one is unknown', () {
      expect(metrics.midClausePauseRatio, isNull);
      expect(metrics.l1FillersPerMin, isNull);
      expect(metrics.repairsPerMin, isNull);
      expect(metrics.efcRatio, isNull);
      expect(metrics.errorsPer100Words, isNull);
      expect(metrics.errorsByTag, isEmpty);
      expect(metrics.meanClauseLength, isNull);
      expect(metrics.subordination, isNull);
      // Five words are far from enough for lexical diversity.
      expect(metrics.mtld, isNull);
      expect(metrics.beyondFrequentShare, isNull);
    });

    test('nothing but hesitation, or no time, gives no measures', () {
      expect(SpeechMetrics.of(const [], language: zz), isNull);
      expect(
        SpeechMetrics.of([
          word('eh', 0, 300),
          word('mm', 400, 600),
        ], language: zz),
        isNull,
      );
      expect(SpeechMetrics.of([word('bada', 500, 500)], language: zz), isNull);
    });
  });

  group('with the annotation', () {
    const annotation = SpeechAnnotation(
      taskOutcome: TaskOutcome.partial,
      clauses: [
        AnnotatedClause(startI: 0, endI: 1, asUnit: 0, errorFree: true),
        AnnotatedClause(startI: 3, endI: 5, asUnit: 1, errorFree: false),
      ],
      errors: [
        SpeechError(
          startI: 4,
          endI: 4,
          tag: 'zz.form',
          correction: 'deru',
          severity: 2,
        ),
      ],
      repairs: [WordSpan(startI: 4, endI: 5)],
    );
    final metrics = SpeechMetrics.of(
      recording,
      language: zz,
      annotation: annotation,
    )!;

    test('a pause inside a clause counts apart', () {
      // After "kolu" the first clause ends; after "sima" the second goes on.
      expect(metrics.midClausePauseRatio, 0.5);
    });

    test('accuracy: error-free clauses and errors per 100 words', () {
      expect(metrics.efcRatio, 0.5);
      expect(metrics.errorsPer100Words, closeTo(20, 1e-9));
      expect(metrics.errorsByTag, {'zz.form': closeTo(20, 1e-9)});
      expect(metrics.repairsPerMin, closeTo(1 / minutes, 1e-9));
      expect(metrics.l1FillersPerMin, 0);
    });

    test('complexity: words per clause and clauses per AS-unit', () {
      expect(metrics.meanClauseLength, 2.5);
      expect(metrics.subordination, 1);
      const joined = SpeechAnnotation(
        taskOutcome: TaskOutcome.done,
        clauses: [
          AnnotatedClause(startI: 0, endI: 1, asUnit: 0, errorFree: true),
          AnnotatedClause(startI: 3, endI: 5, asUnit: 0, errorFree: true),
        ],
      );
      expect(
        SpeechMetrics.of(
          recording,
          language: zz,
          annotation: joined,
        )!.subordination,
        2,
      );
    });

    test("the learner's own hesitation is apart from the language's", () {
      final said = [...recording, word('nana', 4200, 4500)];
      final marked = SpeechMetrics.of(
        said,
        language: zz,
        annotation: const SpeechAnnotation(
          taskOutcome: TaskOutcome.done,
          fillers: [
            SpokenFiller(i: 2, kind: FillerKind.l1),
            SpokenFiller(i: 6, kind: FillerKind.l1),
          ],
        ),
      )!;
      const spoken = 4500 / 60000;
      expect(marked.words, 5);
      expect(marked.l1FillersPerMin, closeTo(2 / spoken, 1e-9));
      expect(marked.filledPausesPerMin, 0);
    });
  });

  test('connectors are counted once each, phrases too', () {
    final metrics = SpeechMetrics.of(
      recording,
      language: zz,
      connectors: ['kolu', 'Sima dero', 'sima, dero', 'nana', ''],
    )!;
    expect(metrics.connectorTypes, 2);
  });

  test('words beyond the frequent ones, among the ranked', () {
    const ranks = {'bada': 10, 'kolu': 2500, 'sima': 30};
    final metrics = SpeechMetrics.of(
      recording,
      language: zz,
      rankOf: (lemma) => ranks[lemma],
    )!;
    // bada, kolu, sima, kolu have ranks; dero has none.
    expect(metrics.beyondFrequentShare, 0.5);
    expect(
      SpeechMetrics.of(
        recording,
        language: zz,
        rankOf: (_) => null,
      )!.beyondFrequentShare,
      isNull,
    );
  });

  test('lexical diversity from the minimum of words', () {
    final many = [
      for (var i = 0; i < 100; i++)
        word(['bada', 'kolu', 'sima', 'dero'][i % 4], i * 500, i * 500 + 400),
    ];
    final metrics = SpeechMetrics.of(many, language: zz)!;
    expect(metrics.mtld, isNotNull);
    final fewer = SpeechMetrics.of(
      recording,
      language: zz,
      config: const SpeechMetricsConfig(mtldMinWords: 5),
    )!;
    expect(fewer.mtld, isNotNull);
  });

  test('stored with the documented names', () {
    final json = SpeechMetrics.of(recording, language: zz)!.toJson();
    expect(
      json.keys,
      containsAll([
        'speaking_ms',
        'speech_rate',
        'articulation_rate',
        'mlr',
        'long_pauses_per_min',
        'mid_clause_pause_ratio',
        'filled_pauses_per_min',
        'l1_fillers_per_min',
        'repairs_per_min',
        'efc_ratio',
        'errors_per_100w',
        'mean_clause_length',
        'subordination',
        'mtld',
        'connector_types',
        'beyond_2k_share',
      ]),
    );
    expect(
      SpeechMetrics.fromJson(json),
      SpeechMetrics.of(recording, language: zz),
    );
  });
}
