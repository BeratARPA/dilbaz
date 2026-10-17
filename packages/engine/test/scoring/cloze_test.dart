import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  final language = PackLanguage(
    rules: const NormalizationRules(version: 1, punctuation: '.,?!"'),
    forms: {
      'mi': {'mi'},
      'bada': {'bada'},
      'badan': {'bada'},
      'kolu': {'kolu'},
      'sima': {'sima'},
    },
  );

  AnswerKey key(String reference, Set<String> lemmas) =>
      AnswerKey(reference: reference, targetLemmas: lemmas);

  group('Cloze (A04)', () {
    test('the gap is the target word; punctuation stays outside', () {
      final cloze = Cloze.of(key('Mi badan kolu.', {'bada'}), language)!;
      expect(
        (cloze.before, cloze.gap, cloze.after),
        ('Mi ', 'badan', ' kolu.'),
      );
      final last = Cloze.of(key('Kolu mi badan?', {'bada'}), language)!;
      expect((last.before, last.gap, last.after), ('Kolu mi ', 'badan', '?'));
      final first = Cloze.of(key('"Bada, kolu."', {'bada'}), language)!;
      expect((first.before, first.gap, first.after), ('"', 'Bada', ', kolu."'));
    });

    test('two target words make one gap from the first to the last', () {
      final cloze = Cloze.of(
        key('Mi bada sima badan kolu.', {'bada'}),
        language,
      )!;
      expect(
        (cloze.before, cloze.gap, cloze.after),
        ('Mi ', 'bada sima badan', ' kolu.'),
      );
    });

    test('no gap without a target, or with nothing around it', () {
      expect(Cloze.of(key('Mi kolu.', {'bada'}), language), isNull);
      expect(Cloze.of(key('Mi kolu.', {}), language), isNull);
      expect(Cloze.of(key('Badan!', {'bada'}), language), isNull);
    });

    test('an answer fills the gap; a whole sentence stays as said', () {
      final cloze = Cloze.of(key('Mi badan kolu.', {'bada'}), language)!;
      expect(cloze.fill(' bada ', language), 'Mi bada kolu.');
      expect(cloze.fill('mi bada kolu', language), 'mi bada kolu');
      final last = Cloze.of(key('Kolu mi badan?', {'bada'}), language)!;
      expect(last.fill('badan', language), 'Kolu mi badan?');
      // Short sentences: one word is the gap, not the sentence.
      final short = Cloze.of(key('Bada kolu.', {'bada'}), language)!;
      expect(short.fill('sima', language), 'sima kolu.');
      expect(short.fill('bada kolu', language), 'bada kolu');
    });
  });
}
