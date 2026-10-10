import 'dart:math';

import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  group('editDistance', () {
    test('equal words are no edit apart', () {
      expect(editDistance('bada', 'bada'), 0);
      expect(editDistance('', ''), 0);
    });

    test('a wrong, a missing and an added letter are one edit each', () {
      expect(editDistance('bada', 'bado'), 1);
      expect(editDistance('bada', 'bda'), 1);
      expect(editDistance('bada', 'badar'), 1);
    });

    test('two swapped neighbours are one edit', () {
      expect(editDistance('bada', 'baad'), 1);
      expect(editDistance('kolu', 'oklu'), 1);
    });

    test('edits add up', () {
      expect(editDistance('bada', 'kolu'), 4);
      expect(editDistance('bada', ''), 4);
      expect(editDistance('', 'kolu'), 4);
      expect(editDistance('søravelin', 'soravelen'), 2);
    });

    test('a letter outside the basic plane is one letter', () {
      expect(editDistance('ba𐐷a', 'bada'), 1);
      expect(editDistance('ʒorin', 'zorin'), 1);
    });

    test('is the same in both directions and never more than the longer', () {
      final random = Random(5);
      const letters = 'abdkløʒ';
      String word() => [
        for (var i = random.nextInt(8); i > 0; i--)
          letters[random.nextInt(letters.length)],
      ].join();
      for (var i = 0; i < 500; i++) {
        final a = word();
        final b = word();
        final distance = editDistance(a, b);
        expect(distance, editDistance(b, a));
        expect(distance, lessThanOrEqualTo(max(a.length, b.length)));
        expect(distance == 0, a == b);
      }
    });
  });
}
