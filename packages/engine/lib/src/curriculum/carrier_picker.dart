import 'package:dilbaz_engine/src/curriculum/carrier_choice.dart';
import 'package:dilbaz_engine/src/curriculum/content_item.dart';
import 'package:dilbaz_engine/src/curriculum/item_kind.dart';
import 'package:dilbaz_engine/src/model/lemma_knowledge.dart';

/// Picks the carriers a new item is introduced with: those whose other
/// words the learner knows (i+1, docs/02-curriculum.md §4.4).
final class CarrierPicker {
  /// A picker; a carrier fits with at most [maxUnknown] other lemmas
  /// expected to be unknown.
  const new({this.maxUnknown = 0.5});

  /// Most other lemmas a fitting carrier may be expected to hide.
  final double maxUnknown;

  /// The [candidates] that carry [target], the best first: fewest other
  /// lemmas expected to be unknown, then shorter, then easier.
  ///
  /// The candidates are the sentences the pack chose for the target; its
  /// `contains` links match lemmas, not senses, and are no substitute. A
  /// chunk with no sentence is its own carrier.
  List<CarrierChoice> pick({
    required ContentItem target,
    required Iterable<ContentItem> candidates,
    required LemmaKnowledge knowledge,
  }) {
    final own = target.lemmas.toSet();
    CarrierChoice choice(ContentItem carrier) {
      final others = carrier.lemmas.toSet().difference(own);
      final unknown = others.fold<double>(
        0,
        (sum, lemma) => sum + 1 - knowledge.probability(lemma),
      );
      return CarrierChoice(
        carrier: carrier,
        unknown: unknown,
        fits: unknown <= maxUnknown,
      );
    }

    final choices =
        [
          for (final sentence in candidates)
            if (sentence.kind == ItemKind.sentence &&
                !sentence.deprecated &&
                sentence.targets.contains(target.key))
              choice(sentence),
        ]..sort((a, b) {
          final byUnknown = a.unknown.compareTo(b.unknown);
          if (byUnknown != 0) return byUnknown;
          final byLength = a.carrier.lemmas.length.compareTo(
            b.carrier.lemmas.length,
          );
          if (byLength != 0) return byLength;
          final byLevel = a.carrier.level.scale.compareTo(
            b.carrier.level.scale,
          );
          return byLevel != 0
              ? byLevel
              : a.carrier.key.compareTo(b.carrier.key);
        });
    if (choices.isEmpty && target.kind == ItemKind.chunk) {
      return [CarrierChoice(carrier: target, unknown: 0, fits: true)];
    }
    return choices;
  }
}
