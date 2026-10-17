import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

MeaningChoice meaning(
  String key,
  String text, {
  ItemKind kind = ItemKind.wordSense,
  CefrLevel level = CefrLevel.a1,
}) => (key: key, kind: kind, level: level, meaning: text);

void main() {
  final target = meaning('zz.bada', 'bada demek');

  test('the meaning and three others of its kind, nearest level first', () {
    final pool = [
      target,
      meaning('zz.kolu', 'kolu demek'),
      meaning('zz.sima', 'sima demek', level: CefrLevel.a2),
      meaning('zz.dero', 'dero demek', level: CefrLevel.c1),
      meaning('zz.mi', 'mi demek', level: CefrLevel.a0),
      meaning('zz.same', ' Bada Demek'),
      meaning('zz.chunk', 'kalıp', kind: ItemKind.chunk),
    ];
    for (final seed in [1, 2, 3, 40]) {
      final choices = pickChoices(target: target, pool: pool, seed: seed)!;
      expect(choices, hasLength(4));
      expect(choices, contains('bada demek'));
      // The C1 meaning is the farthest; the same meaning and another kind
      // never come.
      expect(choices.toSet(), {
        'bada demek',
        'kolu demek',
        'sima demek',
        'mi demek',
      });
    }
    expect(
      pickChoices(target: target, pool: pool, seed: 7),
      pickChoices(target: target, pool: pool, seed: 7),
    );
  });

  test('not enough others: no choices', () {
    expect(
      pickChoices(
        target: target,
        pool: [meaning('zz.kolu', 'kolu demek')],
        seed: 1,
      ),
      isNull,
    );
  });

  test('recognized is Good, not recognized Again', () {
    expect(recognitionRating(recognized: true), ReviewRating.good);
    expect(recognitionRating(recognized: false), ReviewRating.again);
  });
}
