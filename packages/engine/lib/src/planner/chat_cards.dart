import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';

/// A chat card of the pack (A14): its key and the lowest level it suits.
typedef ChatCardRef = ({String key, CefrLevel level});

/// The chat cards to offer, in order (A14): those at the learner's [level]
/// or below (A1 cards from A0 on); the ones not talked about lately first,
/// then by level, then by key. The partners choose (I-14).
List<String> chatCardOrder({
  required List<ChatCardRef> cards,
  required CefrLevel level,
  Set<String> talkedLately = const {},
}) {
  final top = level.index < CefrLevel.a1.index ? CefrLevel.a1 : level;
  final offered =
      [
        for (final card in cards)
          if (card.level.index <= top.index) card,
      ]..sort((a, b) {
        final lately =
            (talkedLately.contains(a.key) ? 1 : 0) -
            (talkedLately.contains(b.key) ? 1 : 0);
        if (lately != 0) return lately;
        final byLevel = a.level.index - b.level.index;
        return byLevel != 0 ? byLevel : a.key.compareTo(b.key);
      });
  return [for (final card in offered) card.key];
}
