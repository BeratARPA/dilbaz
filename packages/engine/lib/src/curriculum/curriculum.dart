import 'dart:math';

import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/curriculum/content_item.dart';
import 'package:dilbaz_engine/src/curriculum/curriculum_config.dart';
import 'package:dilbaz_engine/src/curriculum/item_kind.dart';
import 'package:dilbaz_engine/src/curriculum/item_link.dart';
import 'package:dilbaz_engine/src/curriculum/link_type.dart';
import 'package:dilbaz_engine/src/model/item_level.dart';

/// The order in which new items are introduced
/// (docs/02-curriculum.md §4.3).
final class Curriculum {
  /// A curriculum over a pack's [items] and [links].
  new({
    required Iterable<ContentItem> items,
    required Iterable<ItemLink> links,
    this.config = const CurriculumConfig(),
  }) : _items = [
         for (final item in items)
           if (config.introducible.contains(item.kind) && !item.deprecated)
             item,
       ]..sort((a, b) => a.key.compareTo(b.key)),
       _maxRank = items.fold(1, (most, item) => max(most, item.rank ?? 1)) {
    for (final item in _items) {
      if (item.kind == ItemKind.wordSense && item.lemmas.isNotEmpty) {
        _wordOf[item.key] = item.lemmas.join(_lemmaSeparator);
      }
    }
    for (final link in links) {
      if (link.type == LinkType.requires) {
        (_requires[link.from] ??= {}).add(link.to);
      } else if (link.type == LinkType.contrastsWith) {
        (_contrasts[link.from] ??= {}).add(link.to);
        (_contrasts[link.to] ??= {}).add(link.from);
      }
    }
  }

  /// The weights in use.
  final CurriculumConfig config;

  final List<ContentItem> _items;
  final int _maxRank;
  final _requires = <String, Set<String>>{};
  final _contrasts = <String, Set<String>>{};

  /// Word sense key → its word, to tell the senses of one word.
  final _wordOf = <String, String>{};

  static const _lemmaSeparator = '|';

  /// Keys of the items to introduce next, best first.
  ///
  /// A candidate has no card yet ([levelOf] is [ItemLevel.unseen]) and all
  /// its prerequisites are recallable. No two items of the list are easily
  /// confused with each other or with one of [introducedToday], and no two
  /// are senses of one word: such pairs are never introduced on the same
  /// day (I-10), so any prefix of the list can be introduced today.
  List<String> next({
    required CefrLevel level,
    required ItemLevel Function(String key) levelOf,
    Set<String> personal = const {},
    Set<String> focus = const {},
    Set<String> canDo = const {},
    Set<String> introducedToday = const {},
    Set<String> introducedLately = const {},
  }) {
    final scored =
        [
          for (final item in _items)
            if (levelOf(item.key) == ItemLevel.unseen &&
                (_requires[item.key] ?? const {}).every(
                  (key) => levelOf(key).isAtLeast(ItemLevel.recallable),
                ))
              (
                item: item,
                score: score(
                  item,
                  level: level,
                  personal: personal,
                  focus: focus,
                  canDo: canDo,
                  introducedLately: introducedLately,
                ),
              ),
        ]..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          if (byScore != 0) return byScore;
          final byRank = (a.item.rank ?? _maxRank + 1).compareTo(
            b.item.rank ?? _maxRank + 1,
          );
          return byRank != 0 ? byRank : a.item.key.compareTo(b.item.key);
        });

    final chosen = <String>[];
    final blocked = {for (final key in introducedToday) ...?_contrasts[key]};
    final words = {for (final key in introducedToday) ?_wordOf[key]};
    for (final (:item, score: _) in scored) {
      final word = _wordOf[item.key];
      if (blocked.contains(item.key) || words.contains(word)) continue;
      chosen.add(item.key);
      blocked.addAll(_contrasts[item.key] ?? const {});
      if (word != null) words.add(word);
    }
    return chosen;
  }

  /// The score of [item] as the next new item for a learner at [level].
  double score(
    ContentItem item, {
    required CefrLevel level,
    Set<String> personal = const {},
    Set<String> focus = const {},
    Set<String> canDo = const {},
    Set<String> introducedLately = const {},
  }) {
    final confusable = (_contrasts[item.key] ?? const {}).any(
      introducedLately.contains,
    );
    return (personal.contains(item.key) ? config.personalWeight : 0) +
        config.levelWeight * _levelFit(item.level, level) +
        config.frequencyWeight * _frequency(item.rank) +
        (focus.contains(item.key) ? config.focusWeight : 0) +
        (canDo.contains(item.key) ? config.canDoWeight : 0) -
        (confusable ? config.similarityPenalty : 0);
  }

  /// 1 at the learner's level or one above; less two above or below; 0
  /// further above.
  double _levelFit(CefrLevel item, CefrLevel learner) =>
      switch (item.scale - learner.scale) {
        0 || 1 => 1,
        2 => config.twoAboveFit,
        < 0 => config.belowFit,
        _ => 0,
      };

  /// 1 for the most frequent lemma, 0 for the rarest of the pack.
  double _frequency(int? rank) {
    if (rank == null) return config.unrankedFrequency;
    return _maxRank <= 1 ? 1 : 1 - log(rank) / log(_maxRank);
  }
}
