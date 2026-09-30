import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  group('SeededRandom', () {
    test('gives the same numbers for the same seed', () {
      List<int> draws(int seed) {
        final random = SeededRandom(seed);
        return [for (var i = 0; i < 20; i++) random.nextInt(1000)];
      }

      expect(draws(42), draws(42));
      expect(draws(42), isNot(draws(43)));
      expect(draws(0), everyElement(inInclusiveRange(0, 999)));
    });

    test('shuffles without losing, adding or touching anything', () {
      final items = [for (var i = 0; i < 30; i++) i];
      final shuffled = SeededRandom(9).shuffled(items);
      expect(shuffled, unorderedEquals(items));
      expect(shuffled, isNot(items));
      expect(items, [for (var i = 0; i < 30; i++) i]);
      expect(SeededRandom(9).shuffled(items), shuffled);
      expect(SeededRandom(10).shuffled(items), isNot(shuffled));
    });

    test('shuffles the smallest lists as they are', () {
      expect(SeededRandom(1).shuffled(<int>[]), isEmpty);
      expect(SeededRandom(1).shuffled([7]), [7]);
    });

    test('puts every item everywhere over many seeds', () {
      // Each of 4 items should reach each of 4 places.
      final seen = <(int, int)>{};
      for (var seed = 1; seed <= 200; seed++) {
        final order = SeededRandom(seed).shuffled([0, 1, 2, 3]);
        for (final (place, item) in order.indexed) {
          seen.add((place, item));
        }
      }
      expect(seen, hasLength(16));
    });
  });
}
