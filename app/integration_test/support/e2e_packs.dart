import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/pack_fixture.dart';

/// A word of the synthetic language, the sentence that carries it, and
/// what the card asks in the learner's language.
typedef E2eWord = ({String word, String sentence, String prompt});

/// Five words, each with its own sentence: more than a first session
/// takes.
const List<E2eWord> fiveWords = [
  (word: 'bada', sentence: 'Bada kolu.', prompt: 'Bada kolu de.'),
  (word: 'sima', sentence: 'Sima dero.', prompt: 'Sima dero de.'),
  (word: 'dero', sentence: 'Dero lumo.', prompt: 'Dero lumo de.'),
  (word: 'lumo', sentence: 'Lumo tavi.', prompt: 'Lumo tavi de.'),
  (word: 'tavi', sentence: 'Tavi bada.', prompt: 'Tavi bada de.'),
];

/// The word of the card on the screen, by the prompt it shows.
E2eWord wordAsked() => fiveWords.singleWhere(
  (word) => find.text(word.prompt).evaluate().isNotEmpty,
);

/// Installs a target and a pair pack of [fiveWords] the way the app
/// imports downloaded packs.
Future<void> installFiveWords(AppDatabase db) async {
  const target = 'zz@1';
  const pair = 'qq-zz@1';
  String wordKey(E2eWord w) => 'zz.ws.${w.word}.n.1';
  String sentenceKey(int i) => 'zz.sent.e$i';
  final packs = [
    await buildPack(
      id: target,
      kind: 'target',
      manifest: {
        'min_engine_version': 1,
        'script': {'direction': 'ltr', 'word_separator': 'space'},
      },
      normalization: soundNormalization,
      items: [
        for (final (i, w) in fiveWords.indexed) ...[
          item(
            wordKey(w),
            'word_sense',
            packId: target,
            text: w.word,
            lemmas: [w.word],
            rank: 10 * (i + 1),
            data: {
              'carriers': [sentenceKey(i)],
            },
          ),
          item(
            sentenceKey(i),
            'sentence',
            packId: target,
            text: w.sentence,
            lemmas: w.sentence.toLowerCase().replaceAll('.', '').split(' '),
            targets: [wordKey(w)],
          ),
        ],
      ],
      forms: [
        for (final form in {for (final w in fiveWords) w.word, 'kolu'})
          ContentFormsCompanion.insert(form: form, lemma: form, packId: target),
      ],
    ),
    await buildPack(
      id: pair,
      kind: 'pair',
      l1: 'qq',
      pairEntries: [
        for (final (i, w) in fiveWords.indexed) ...[
          ContentPairEntriesCompanion.insert(
            kind: 'gloss',
            key: wordKey(w),
            packId: pair,
            data: {'meaning': '${w.word} demek'},
          ),
          ContentPairEntriesCompanion.insert(
            kind: 'gloss',
            key: sentenceKey(i),
            packId: pair,
            data: {'meaning': w.prompt},
          ),
        ],
      ],
    ),
  ];
  for (final built in packs) {
    final result = await PackImporter(db).import(built.bytes, built.info);
    expect(result, isA<Ok<void, PackFailure>>(), reason: built.info.id);
  }
}
