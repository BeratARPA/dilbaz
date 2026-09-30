import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/pack_info.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// A pack file and its registry row.
typedef BuiltPack = ({PackInfo info, Uint8List bytes});

/// An empty in-memory app database.
AppDatabase memoryDatabase() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

/// Normalization rules whose own example holds.
const Map<String, Object?> soundNormalization = {
  'version': 1,
  'punctuation': '.',
  'tests': [
    ['Bada Kolu.', 'bada kolu'],
  ],
};

/// Builds a pack file the way `dilbaz-content build` lays it out
/// (docs/11-language-packs.md §5.1): the app's own content tables, a
/// `pack_meta` table and the format version.
Future<BuiltPack> buildPack({
  required String id,
  required String kind,
  String l2 = 'zz',
  String? l1,
  double version = 1,
  int formatVersion = PackImporter.formatVersion,
  List<ContentItemsCompanion> items = const [],
  List<ContentLinksCompanion> links = const [],
  List<ContentFormsCompanion> forms = const [],
  List<ContentPairEntriesCompanion> pairEntries = const [],
  Map<String, Object?> manifest = const {},
  Map<String, Object?>? normalization,
}) async {
  // The fixture is a second database on its own file.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final directory = await Directory.systemTemp.createTemp('dilbaz_fixture');
  final file = File('${directory.path}${Platform.pathSeparator}pack.sqlite');
  final db = AppDatabase(NativeDatabase(file));
  try {
    await db.batch((batch) {
      batch
        ..insertAll(db.contentItems, items)
        ..insertAll(db.contentLinks, links)
        ..insertAll(db.contentForms, forms)
        ..insertAll(db.contentPairEntries, pairEntries);
    });
    await db.customStatement(
      'CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    final meta = <String, Object?>{
      'format_version': formatVersion,
      'manifest': {'id': id, 'kind': kind, 'l2': l2, 'l1': l1, ...manifest},
      'normalization': ?normalization,
    };
    for (final MapEntry(:key, :value) in meta.entries) {
      await db.customStatement(
        'INSERT INTO pack_meta (key, value) VALUES (?, ?)',
        [key, jsonEncode(value)],
      );
    }
    await db.customStatement('PRAGMA user_version = $formatVersion');
  } finally {
    await db.close();
  }
  final bytes = await file.readAsBytes();
  await directory.delete(recursive: true);
  return (
    info: PackInfo(
      id: id,
      kind: kind,
      l2: l2,
      l1: l1,
      version: version,
      checksum: 'sha256:${sha256.convert(bytes)}',
      storagePath: 'packs/$id.sqlite',
    ),
    bytes: bytes,
  );
}

ContentItemsCompanion item(
  String key,
  String kind, {
  required String packId,
  String level = 'A1',
  String? text,
  List<String> lemmas = const [],
  List<String> targets = const [],
  int? rank,
  Map<String, Object?> data = const {},
}) => ContentItemsCompanion.insert(
  key: key,
  packId: packId,
  kind: kind,
  level: level,
  textL2: Value(text),
  lemmas: Value(lemmas),
  targets: Value(targets),
  rank: Value(rank),
  data: Value(data),
);

/// A small target pack of the synthetic language: two words, a chunk and a
/// sentence.
Future<BuiltPack> targetPack({
  String id = 'zz@1',
  double version = 1,
  String word = 'bada',
  Map<String, Object?>? normalization = soundNormalization,
  Map<String, Object?> manifest = const {},
  int formatVersion = PackImporter.formatVersion,
}) => buildPack(
  id: id,
  kind: 'target',
  version: version,
  formatVersion: formatVersion,
  manifest: {
    'min_engine_version': 1,
    'script': {'direction': 'ltr', 'word_separator': 'space'},
    ...manifest,
  },
  normalization: normalization,
  items: [
    item(
      'zz.ws.$word.n.1',
      'word_sense',
      packId: id,
      text: word,
      lemmas: [word],
      rank: 12,
      data: {
        'carriers': ['zz.sent.0001'],
      },
    ),
    item('zz.ws.kolu.v.1', 'word_sense', packId: id, text: 'kolu', rank: 40),
    item('zz.chunk.${word}_kolu', 'chunk', packId: id, text: '$word kolu'),
    item(
      'zz.sent.0001',
      'sentence',
      packId: id,
      text: '${word[0].toUpperCase()}${word.substring(1)} kolu.',
      lemmas: [word, 'kolu'],
      targets: ['zz.ws.$word.n.1', 'zz.ws.kolu.v.1'],
    ),
    item('zz.lemma.$word', 'lemma', packId: id, text: word, rank: 12),
  ],
  links: [
    ContentLinksCompanion.insert(
      fromKey: 'zz.sent.0001',
      toKey: 'zz.ws.$word.n.1',
      type: 'contains',
      packId: id,
    ),
  ],
  forms: [
    ContentFormsCompanion.insert(form: word, lemma: word, packId: id),
    ContentFormsCompanion.insert(form: '${word}ven', lemma: word, packId: id),
    ContentFormsCompanion.insert(form: 'kolu', lemma: 'kolu', packId: id),
  ],
);

/// The pair pack that goes with [targetPack].
Future<BuiltPack> pairPack({String id = 'qq-zz@1', double version = 1}) =>
    buildPack(
      id: id,
      kind: 'pair',
      l1: 'qq',
      version: version,
      pairEntries: [
        ContentPairEntriesCompanion.insert(
          kind: 'gloss',
          key: 'zz.ws.bada.n.1',
          packId: id,
          data: const {'meaning': 'anlam'},
        ),
        ContentPairEntriesCompanion.insert(
          kind: 'variants',
          key: 'zz.sent.0001',
          packId: id,
          data: const {
            'variants': ['Kolu bada.'],
          },
        ),
      ],
      links: [
        ContentLinksCompanion.insert(
          fromKey: 'zz.ws.bada.n.1',
          toKey: 'zz.ws.kolu.v.1',
          type: 'contrasts_with',
          packId: id,
        ),
      ],
    );
