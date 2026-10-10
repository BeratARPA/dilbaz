import 'dart:math';

import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

import '../fixtures/zz/zz_pack.dart';

void main() {
  final zz = ZzPack.generate();
  final curriculum = Curriculum(items: zz.items, links: zz.links);
  const config = CurriculumConfig();
  ItemLevel unseen(String key) => ItemLevel.unseen;
  final contrasts = [
    for (final link in zz.links)
      if (link.type == LinkType.contrastsWith) link,
  ];
  final requires = [
    for (final link in zz.links)
      if (link.type == LinkType.requires) link,
  ];

  group('Curriculum.next (docs/02-curriculum.md §4.3)', () {
    test('offers words and chunks without a card, best first', () {
      final next = curriculum.next(level: CefrLevel.a1, levelOf: unseen);
      final kinds = {for (final key in next) zz.item(key).kind};
      expect(kinds, {ItemKind.wordSense, ItemKind.chunk});
      expect(next.toSet(), hasLength(next.length));
      final scores = [
        for (final key in next)
          curriculum.score(zz.item(key), level: CefrLevel.a1),
      ];
      expect(scores, [...scores]..sort((a, b) => b.compareTo(a)));
    });

    test('skips items that have a card', () {
      final all = curriculum.next(level: CefrLevel.a1, levelOf: unseen);
      final learning = all.take(5).toSet();
      final next = curriculum.next(
        level: CefrLevel.a1,
        levelOf: (key) =>
            learning.contains(key) ? ItemLevel.learning : ItemLevel.unseen,
      );
      expect(next.toSet().intersection(learning), isEmpty);
    });

    test('waits for prerequisites to be recallable', () {
      expect(requires, isNotEmpty);
      final blocked = {for (final link in requires) link.from};
      final open = curriculum.next(level: CefrLevel.a1, levelOf: unseen);
      expect(open.toSet().intersection(blocked), isEmpty);

      final link = requires.first;
      List<String> nextWith(ItemLevel prerequisite) => curriculum.next(
        level: CefrLevel.a1,
        levelOf: (key) => key == link.to ? prerequisite : ItemLevel.unseen,
      );
      expect(nextWith(ItemLevel.learning), isNot(contains(link.from)));
      expect(nextWith(ItemLevel.recallable), contains(link.from));
      expect(nextWith(ItemLevel.durable), contains(link.from));
    });

    test('pairs that are easily confused never come on the same day', () {
      // docs/05-session-planner.md §8, item 10.
      expect(contrasts, isNotEmpty);
      final next = curriculum.next(level: CefrLevel.a1, levelOf: unseen);
      final listed = next.toSet();
      for (final link in contrasts) {
        expect(
          listed.contains(link.from) && listed.contains(link.to),
          isFalse,
          reason: '${link.from} / ${link.to}',
        );
      }
      // The better one of a pair is kept.
      final pair = contrasts.first;
      expect(listed.contains(pair.from) || listed.contains(pair.to), isTrue);

      // Introduced today: its partner waits for another day.
      final today = curriculum.next(
        level: CefrLevel.a1,
        levelOf: (key) =>
            key == pair.from ? ItemLevel.learning : ItemLevel.unseen,
        introducedToday: {pair.from},
      );
      expect(today, isNot(contains(pair.to)));
      final tomorrow = curriculum.next(
        level: CefrLevel.a1,
        levelOf: (key) =>
            key == pair.from ? ItemLevel.learning : ItemLevel.unseen,
        introducedLately: {pair.from},
      );
      expect(tomorrow, contains(pair.to));
    });

    test('does not depend on the order of the pack lists', () {
      final shuffled = Curriculum(
        items: [...zz.items]..shuffle(Random(1)),
        links: [...zz.links]..shuffle(Random(2)),
      );
      expect(
        shuffled.next(level: CefrLevel.a2, levelOf: unseen),
        curriculum.next(level: CefrLevel.a2, levelOf: unseen),
      );
    });

    test('two senses of one word never come on the same day', () {
      final senses = zz.ofKind(ItemKind.wordSense);
      final second = senses.firstWhere((sense) => sense.key.endsWith('.2'));
      final first = senses.firstWhere(
        (sense) =>
            sense.lemmas.single == second.lemmas.single && sense != second,
      );
      final next = curriculum.next(level: CefrLevel.a1, levelOf: unseen);
      final words = [
        for (final key in next)
          if (zz.item(key).kind == ItemKind.wordSense)
            zz.item(key).lemmas.single,
      ];
      expect(words.toSet(), hasLength(words.length));
      expect(next.contains(first.key) != next.contains(second.key), isTrue);

      // One sense introduced today: the other waits; tomorrow it is free.
      final listed = next.contains(first.key) ? first : second;
      final waiting = listed == first ? second : first;
      ItemLevel levelOf(String key) =>
          key == listed.key ? ItemLevel.learning : ItemLevel.unseen;
      expect(
        curriculum.next(
          level: CefrLevel.a1,
          levelOf: levelOf,
          introducedToday: {listed.key},
        ),
        isNot(contains(waiting.key)),
      );
      expect(
        curriculum.next(level: CefrLevel.a1, levelOf: levelOf),
        contains(waiting.key),
      );
    });

    test('leaves out deprecated items', () {
      final first = curriculum.next(level: CefrLevel.a1, levelOf: unseen).first;
      final pruned = Curriculum(
        items: [
          for (final item in zz.items)
            if (item.key == first) item.copyWith(deprecated: true) else item,
        ],
        links: zz.links,
      );
      expect(
        pruned.next(level: CefrLevel.a1, levelOf: unseen),
        isNot(contains(first)),
      );
    });
  });

  group('Curriculum.score (docs/02-curriculum.md §4.3)', () {
    ContentItem sense({required CefrLevel level, int? rank}) => ContentItem(
      key: 'zz.ws.x.n.1',
      kind: ItemKind.wordSense,
      level: level,
      rank: rank,
    );
    final maxRank = zz.lexicon.length;
    double score(ContentItem item, {CefrLevel level = CefrLevel.a1}) =>
        curriculum.score(item, level: level);

    test('level fit: the learner level or one above counts fully', () {
      double fit(CefrLevel item) =>
          score(
            sense(level: item, rank: maxRank),
            level: CefrLevel.a2,
          ) /
          config.levelWeight;
      expect(fit(CefrLevel.a2), 1);
      expect(fit(CefrLevel.b1), 1);
      expect(fit(CefrLevel.b2), config.twoAboveFit);
      expect(fit(CefrLevel.c1), 0);
      expect(fit(CefrLevel.a1), config.belowFit);
      expect(fit(CefrLevel.a0), config.belowFit);
    });

    test('frequency: from 1 for the first rank to 0 for the last', () {
      double frequency(int? rank) =>
          (score(sense(level: CefrLevel.a1, rank: rank)) - config.levelWeight) /
          config.frequencyWeight;
      expect(frequency(1), 1);
      expect(frequency(maxRank), closeTo(0, 1e-9));
      expect(frequency(20), closeTo(1 - log(20) / log(maxRank), 1e-9));
      expect(frequency(10), greaterThan(frequency(100)));
      // A chunk has no rank of its own.
      expect(frequency(null), config.unrankedFrequency);
    });

    test('what the learner asked for outweighs level and frequency', () {
      final rare = sense(level: CefrLevel.b1, rank: maxRank);
      final common = sense(level: CefrLevel.a1, rank: 1);
      expect(
        curriculum.score(rare, level: CefrLevel.a1, personal: {rare.key}),
        greaterThan(curriculum.score(common, level: CefrLevel.a1)),
      );
    });

    test('the weekly focus and an unproven can-do add their weights', () {
      final item = sense(level: CefrLevel.a1, rank: 50);
      final plain = score(item);
      expect(
        curriculum.score(item, level: CefrLevel.a1, focus: {item.key}) - plain,
        closeTo(config.focusWeight, 1e-9),
      );
      expect(
        curriculum.score(item, level: CefrLevel.a1, canDo: {item.key}) - plain,
        closeTo(config.canDoWeight, 1e-9),
      );
    });

    test('an item confusable with a recent one is pushed back', () {
      final pair = contrasts.first;
      final item = zz.item(pair.to);
      final plain = score(item);
      for (final recent in [pair.from]) {
        expect(
          plain -
              curriculum.score(
                item,
                level: CefrLevel.a1,
                introducedLately: {recent},
              ),
          closeTo(config.similarityPenalty, 1e-9),
        );
      }
      // The link holds in both directions.
      final other = zz.item(pair.from);
      expect(
        curriculum.score(
          other,
          level: CefrLevel.a1,
          introducedLately: {pair.to},
        ),
        closeTo(score(other) - config.similarityPenalty, 1e-9),
      );
    });

    test('a pack of one rank has full frequency', () {
      final single = Curriculum(
        items: [sense(level: CefrLevel.a1, rank: 1)],
        links: const [],
      );
      expect(
        single.score(sense(level: CefrLevel.a1, rank: 1), level: CefrLevel.a1),
        config.levelWeight + config.frequencyWeight,
      );
    });
  });
}
