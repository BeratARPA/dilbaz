import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  test('one word over and over: a factor every two words', () {
    expect(mtld(List.filled(100, 'bada')), 2);
  });

  test('the last stretch counts by how far its ratio fell', () {
    // Ratios 1, 1, 1, 0.75: no whole factor; (1 − 0.75) / (1 − 0.72).
    const factor = 0.25 / 0.28;
    expect(mtld(['bada', 'kolu', 'sima', 'bada']), closeTo(4 / factor, 1e-9));
  });

  test('more varied words, a higher diversity', () {
    final plain = [
      for (var i = 0; i < 120; i++) ['bada', 'kolu', 'sima'][i % 3],
    ];
    final varied = [
      for (var i = 0; i < 120; i++)
        ['bada', 'kolu', 'sima', 'dero', 'nana', 'lomi', 'tepa'][i % 7],
    ];
    expect(mtld(varied), greaterThan(mtld(plain)!));
  });

  test('nothing to tell: no words, or no stretch ever ends', () {
    expect(mtld(const []), isNull);
    expect(mtld(['bada', 'kolu', 'sima']), isNull);
  });
}
