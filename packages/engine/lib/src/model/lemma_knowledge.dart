import 'package:dilbaz_engine/src/curriculum/content_item.dart';
import 'package:dilbaz_engine/src/curriculum/item_kind.dart';
import 'package:dilbaz_engine/src/model/item_evidence.dart';
import 'package:dilbaz_engine/src/model/xlex_result.dart';

/// What the learner is taken to know of the target language's lemmas, for
/// personal coverage (I-06, docs/06-assessment.md §2).
///
/// A lemma known through cards counts as known. Any other lemma is known
/// with the probability of its frequency band in the latest X_Lex result,
/// so the estimate gives way to evidence as cards accumulate.
final class LemmaKnowledge {
  /// Knowledge from the lemmas [known] through cards, the pack's frequency
  /// [ranks] and the latest [xlex] result, if any.
  const new({required this.known, required this.ranks, this.xlex});

  /// Knowledge from the learner's cards: a lemma is known when one of its
  /// word senses is produced at the recallable level or recognized
  /// ([evidence] by item key).
  factory fromCards({
    required Iterable<ContentItem> items,
    required Map<String, ItemEvidence> evidence,
    required Map<String, int> ranks,
    XlexResult? xlex,
  }) => LemmaKnowledge(
    known: {
      for (final item in items)
        if (item.kind == ItemKind.wordSense &&
            (evidence[item.key]?.isKnown ?? false))
          ...item.lemmas,
    },
    ranks: ranks,
    xlex: xlex,
  );

  /// Lemmas of items produced at the recallable level or recognized.
  final Set<String> known;

  /// Lemma → frequency rank in the target pack (1 is the most frequent).
  final Map<String, int> ranks;

  /// The latest X_Lex result; null before any test.
  final XlexResult? xlex;

  /// Probability that the learner knows [lemma]. A lemma outside the pack's
  /// lexicon counts as unknown, as does any lemma without a card before the
  /// first test.
  double probability(String lemma) {
    if (known.contains(lemma)) return 1;
    final rank = ranks[lemma];
    final result = xlex;
    if (rank == null || result == null) return 0;
    return result.probability(XlexResult.bandOf(rank));
  }

  /// Personal coverage of a text with these [lemmas]: their mean
  /// probability of being known; 1 for a text without words.
  double coverage(Iterable<String> lemmas) {
    var count = 0;
    var sum = 0.0;
    for (final lemma in lemmas) {
      count++;
      sum += probability(lemma);
    }
    return count == 0 ? 1 : sum / count;
  }
}
