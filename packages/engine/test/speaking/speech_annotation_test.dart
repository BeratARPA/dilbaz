import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';

void main() {
  test("reads the route's annotation as stored", () {
    final annotation = SpeechAnnotation.fromJson(const {
      'task_outcome': 'not_done',
      'clauses': [
        {'start_i': 0, 'end_i': 2, 'as_unit': 0, 'error_free': false},
      ],
      'errors': [
        {
          'start_i': 1,
          'end_i': 1,
          'tag': 'zz.form',
          'correction': 'kolu',
          'severity': 2,
        },
      ],
      'fillers': [
        {'i': 3, 'kind': 'l1'},
      ],
      'repairs': [
        {'start_i': 0, 'end_i': 1},
      ],
      'structures_used': [
        {'code': 'zz.gp.1', 'start_i': 0, 'end_i': 2, 'correct': true},
      ],
      'strengths': ['bada doğru.'],
      'corrections': [
        {
          'original': 'Bada kulu.',
          'corrected': 'Bada kolu.',
          'meaning_l1': 'Bada kolu demek.',
          'tag': 'zz.form',
          'severity': 2,
          'ladder': {'h1': 'tür', 'h2': 'yer', 'h3': 'kural'},
        },
      ],
    });
    expect(annotation.taskOutcome, TaskOutcome.notDone);
    expect(annotation.clauses.single.errorFree, isFalse);
    expect(annotation.errors.single.correction, 'kolu');
    expect(annotation.fillers.single.kind, FillerKind.l1);
    expect(annotation.repairs.single, const WordSpan(startI: 0, endI: 1));
    expect(annotation.structuresUsed.single.code, 'zz.gp.1');
    expect(annotation.corrections.single.ladder.h3, 'kural');
    expect(annotation.corrections.single.meaningL1, 'Bada kolu demek.');
    expect(SpeechAnnotation.fromJson(annotation.toJson()), annotation);
  });

  test('lists may be missing; the outcome may not', () {
    expect(
      SpeechAnnotation.fromJson(const {'task_outcome': 'done'}).errors,
      isEmpty,
    );
    for (final json in [
      const <String, Object?>{},
      const {
        'task_outcome': 'done',
        'clauses': [
          {'start_i': 'one', 'end_i': 2, 'as_unit': 0, 'error_free': true},
        ],
      },
    ]) {
      expect(
        () => SpeechAnnotation.fromJson(json),
        throwsA(isA<CheckedFromJsonException>()),
      );
    }
  });

  test('words keep their times as recognized', () {
    const json = {'w': 'bada', 'start_ms': 120, 'end_ms': 480, 'conf': 0.9};
    final word = TimedWord.fromJson(json);
    expect(
      word,
      const TimedWord(text: 'bada', startMs: 120, endMs: 480, confidence: 0.9),
    );
    expect(word.toJson(), json);
  });
}
