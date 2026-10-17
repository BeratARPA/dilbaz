import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  group('fluencyRounds (A12)', () {
    test('three shorter rounds, by level', () {
      List<int> seconds(CefrLevel level) => [
        for (final round in fluencyRounds(level)) round.inSeconds,
      ];
      expect(seconds(CefrLevel.a0), [90, 60, 45]);
      expect(seconds(CefrLevel.a1), [90, 60, 45]);
      expect(seconds(CefrLevel.a2), [120, 90, 60]);
      expect(seconds(CefrLevel.b1), [240, 180, 120]);
      expect(seconds(CefrLevel.c2), [240, 180, 120]);
    });

    test('each round is shorter than the one before', () {
      for (final level in CefrLevel.values) {
        final rounds = fluencyRounds(level);
        expect(rounds, hasLength(3));
        expect(rounds[1] < rounds[0] && rounds[2] < rounds[1], isTrue);
      }
    });
  });

  group('fluencyTopics (A12 step 1)', () {
    final monday = DateTime.utc(2026, 10, 5);
    test('only topics spoken about; the freshest first', () {
      expect(
        fluencyTopics(
          spoken: [
            (key: 'zz.task.home', lastSpoken: monday),
            (
              key: 'zz.task.city',
              lastSpoken: monday.add(const Duration(days: 2)),
            ),
            (
              key: 'zz.task.park',
              lastSpoken: monday.add(const Duration(days: 1)),
            ),
          ],
        ),
        ['zz.task.city', 'zz.task.park', 'zz.task.home'],
      );
      expect(fluencyTopics(spoken: const []), isEmpty);
    });

    test('a topic told in a 4/3/2 lately goes last', () {
      expect(
        fluencyTopics(
          spoken: [
            (key: 'zz.task.home', lastSpoken: monday),
            (
              key: 'zz.task.city',
              lastSpoken: monday.add(const Duration(days: 2)),
            ),
          ],
          toldLately: {'zz.task.city'},
        ),
        ['zz.task.home', 'zz.task.city'],
      );
    });

    test('a tie keeps the key order', () {
      expect(
        fluencyTopics(
          spoken: [
            (key: 'zz.task.b', lastSpoken: monday),
            (key: 'zz.task.a', lastSpoken: monday),
          ],
        ),
        ['zz.task.a', 'zz.task.b'],
      );
    });
  });
}
