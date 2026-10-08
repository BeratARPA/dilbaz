import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

const ladder = CorrectionLadder(h1: 'tür', h2: 'yer', h3: 'kural');

SpeechCorrection correction(String original, String tag, {int severity = 1}) =>
    SpeechCorrection(
      original: original,
      corrected: '$original!',
      tag: tag,
      severity: severity,
      ladder: ladder,
    );

SpeechError error(String tag) =>
    SpeechError(startI: 0, endI: 0, tag: tag, correction: 'x', severity: 1);

void main() {
  test('persistent tags, then broken meaning, then frequent tags', () {
    final annotation = SpeechAnnotation(
      taskOutcome: TaskOutcome.done,
      errors: [error('zz.b'), error('zz.b'), error('zz.c')],
      corrections: [
        correction('Bada.', 'zz.c'),
        correction('Kolu.', 'zz.b'),
        correction('Sima.', 'zz.d', severity: 3),
        correction('Dero.', 'zz.a'),
      ],
    );
    expect(
      pickCorrections(
        annotation,
        persistentTags: {'zz.a'},
      ).map((c) => c.original),
      ['Dero.', 'Sima.', 'Kolu.'],
    );
    expect(pickCorrections(annotation).map((c) => c.original), [
      'Sima.',
      'Kolu.',
      'Bada.',
    ]);
  });

  test("ties keep the annotation's order; a sentence counts once", () {
    final annotation = SpeechAnnotation(
      taskOutcome: TaskOutcome.partial,
      corrections: [
        correction('Bada.', 'zz.a'),
        correction(' Bada.', 'zz.b'),
        correction('Kolu.', 'zz.a'),
      ],
    );
    expect(pickCorrections(annotation).map((c) => c.original), [
      'Bada.',
      'Kolu.',
    ]);
    expect(pickCorrections(annotation, count: 1), hasLength(1));
    expect(
      pickCorrections(const SpeechAnnotation(taskOutcome: TaskOutcome.done)),
      isEmpty,
    );
  });
}
