import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/curriculum/item_kind.dart';
import 'package:dilbaz_engine/src/fsrs/review_rating.dart';
import 'package:dilbaz_engine/src/planner/seeded_random.dart';

/// An item's meaning in the learner's language, as a choice of a
/// listen-and-understand card (A03).
typedef MeaningChoice = ({
  String key,
  ItemKind kind,
  CefrLevel level,
  String meaning,
});

/// The meanings a listen-and-understand card offers (A03): the item's own
/// and [count] − 1 others, in an order drawn from [seed]; null when there
/// are not enough others.
///
/// The others are items of the same kind with a different meaning, those
/// nearest the item's level first, so a choice is not given away by being
/// much harder or easier.
List<String>? pickChoices({
  required MeaningChoice target,
  required List<MeaningChoice> pool,
  required int seed,
  int count = 4,
}) {
  String plain(String text) => text.trim().toLowerCase();
  final own = plain(target.meaning);
  final seen = {own};
  final others = [
    for (final choice in SeededRandom(seed).shuffled(pool))
      if (choice.key != target.key &&
          choice.kind == target.kind &&
          seen.add(plain(choice.meaning)))
        choice,
  ];
  if (others.length < count - 1) return null;
  int distance(MeaningChoice c) => (c.level.index - target.level.index).abs();
  // A stable sort keeps the drawn order within a distance.
  final indexed = others.indexed.toList()
    ..sort((a, b) {
      final near = distance(a.$2) - distance(b.$2);
      return near != 0 ? near : a.$1 - b.$1;
    });
  return SeededRandom(seed + 1).shuffled([
    target.meaning,
    for (final (_, choice) in indexed.take(count - 1)) choice.meaning,
  ]);
}

/// The rating of a listen-and-understand card: one choice, so the meaning
/// was recognized (Good) or not (Again); no Easy, no Hard (docs/03 §0.3).
ReviewRating recognitionRating({required bool recognized}) =>
    recognized ? ReviewRating.good : ReviewRating.again;
