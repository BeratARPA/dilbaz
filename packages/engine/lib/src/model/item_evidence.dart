import 'package:dilbaz_engine/src/fsrs/mode_group.dart';
import 'package:dilbaz_engine/src/model/card_record.dart';
import 'package:dilbaz_engine/src/model/item_level.dart';

/// The cards of one item and the levels they show
/// (docs/04-learner-model.md §3).
final class ItemEvidence {
  /// Evidence from an item's [cards]; none for an item never introduced.
  const new(this.cards);

  /// The item's cards, one per mode.
  final List<CardRecord> cards;

  /// Production level: the best of the production cards. Recognition never
  /// counts as production (I-05).
  ItemLevel productionLevel({required DateTime now}) {
    var best = ItemLevel.unseen;
    for (final card in cards) {
      if (card.mode.group != ModeGroup.production) continue;
      final level = card.level(now: now);
      if (level.isAtLeast(best)) best = level;
    }
    return best;
  }

  /// Receptive level "recognized": a listening or dictation card recalled
  /// with a stability of a week or more.
  bool get isRecognized => cards.any(
    (card) => card.mode.group != ModeGroup.production && card.isRecallable,
  );

  /// Known when reading or listening (docs/06-assessment.md §2): produced
  /// at the recallable level or recognized.
  bool get isKnown => cards.any((card) => card.isRecallable);
}
