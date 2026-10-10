import 'package:dilbaz_engine/src/curriculum/item_kind.dart';
import 'package:dilbaz_engine/src/language/language_services.dart';
import 'package:dilbaz_engine/src/model/item_evidence.dart';
import 'package:dilbaz_engine/src/model/item_level.dart';
import 'package:dilbaz_engine/src/speaking/speech_annotation.dart';
import 'package:dilbaz_engine/src/speaking/timed_word.dart';

/// An item as free production can show it: its key, kind and lemmas in
/// order.
typedef UsableItem = ({String key, ItemKind kind, List<String> lemmas});

/// Days of error-free free use that make an item "used" (docs/04 §3).
const transferDays = 2;

/// The items used without error in a transcript (docs/04 §3): a word sense
/// whose lemma one of the words has, a chunk whose lemmas follow one
/// another in order. A use counts when no marked error touches its words;
/// hesitations are skipped.
///
/// The words' lemmas do not tell a word's sense apart: a use counts for
/// every sense of the lemma.
Set<String> usedWithoutError(
  List<TimedWord> words, {
  required SpeechAnnotation annotation,
  required Iterable<UsableItem> items,
  required LanguageServices language,
}) {
  final skipped = {
    for (final filler in annotation.fillers) filler.i,
    for (final (i, word) in words.indexed)
      if (language.isFiller(word.text)) i,
  };
  final wrong = {
    for (final error in annotation.errors)
      for (var i = error.startI; i <= error.endI; i++) i,
  };
  // The tokens of the speech, each with its word and its lemmas.
  final tokens = <({int word, Set<String> lemmas})>[
    for (final (i, word) in words.indexed)
      if (!skipped.contains(i))
        for (final token in language.tokenize(word.text))
          (word: i, lemmas: language.lemmasOf(token)),
  ];
  bool clean(int from, int count) =>
      [for (var k = from; k < from + count; k++) tokens[k].word]
          .every((word) => !wrong.contains(word));

  final used = <String>{};
  for (final item in items) {
    final lemmas = item.lemmas;
    if (lemmas.isEmpty) continue;
    if (item.kind != ItemKind.wordSense && item.kind != ItemKind.chunk) {
      continue;
    }
    for (var t = 0; t + lemmas.length <= tokens.length; t++) {
      var match = true;
      for (var k = 0; k < lemmas.length && match; k++) {
        match = tokens[t + k].lemmas.contains(lemmas[k]);
      }
      if (match && clean(t, lemmas.length)) {
        used.add(item.key);
        break;
      }
    }
  }
  return used;
}

/// What the Progress tab counts (docs/04 §3): items known (produced or
/// recognized), recallable, durable, and used in free production. Counts,
/// never percentages (I-04).
typedef EvidenceCounts = ({int known, int recallable, int durable, int used});

/// The counts of [evidence] at [now]; [freeUseDays] gives, per item, the
/// days it was used without error in free production.
EvidenceCounts countEvidence(
  Map<String, ItemEvidence> evidence, {
  required DateTime now,
  Map<String, int> freeUseDays = const {},
}) {
  var known = 0;
  var recallable = 0;
  var durable = 0;
  var used = 0;
  for (final MapEntry(:key, :value) in evidence.entries) {
    // Use in free speech adds to recall; it does not make an item durable.
    final level = value.productionLevel(now: now);
    if (value.isKnown || level.isAtLeast(ItemLevel.recallable)) known++;
    if (level.isAtLeast(ItemLevel.recallable)) recallable++;
    if (level.isAtLeast(ItemLevel.durable)) durable++;
    final days = freeUseDays[key] ?? 0;
    if (withTransfer(level, days) == ItemLevel.transferred) used++;
  }
  return (known: known, recallable: recallable, durable: durable, used: used);
}

/// [level] raised to [ItemLevel.transferred] when the item is recallable
/// and was used without error on [days] days of free production.
ItemLevel withTransfer(ItemLevel level, int days) =>
    level.isAtLeast(ItemLevel.recallable) && days >= transferDays
    ? ItemLevel.transferred
    : level;
