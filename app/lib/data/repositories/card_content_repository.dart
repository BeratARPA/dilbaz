import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/card_content.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators;

/// The target and pair packs as the card session reads them
/// (docs/11-language-packs.md §5.1; docs/02 §4.4 for the carriers).
abstract interface class CardContentRepository {
  /// The target pack's items, as the curriculum sees them.
  Future<List<ContentItem>> items();

  /// The links between them (prerequisites, contrasts).
  Future<List<ItemLink>> links();

  /// The target pack's language services; null before its import.
  Future<PackLanguage?> language();

  /// The learner's own items of the course (A19), as the curriculum sees
  /// them: each is one phrase to say, like a chunk. Without a level of its
  /// own an item is at the learner's [level].
  Future<List<ContentItem>> personalItems(String courseId, CefrLevel level);

  /// What a card of [itemKey] shows and checks, with the carrier that fits
  /// what the learner knows best; null when the packs cannot make one.
  Future<CardContent?> content(
    String itemKey, {
    required LemmaKnowledge knowledge,
  });

  /// The packs' sentences that have audio, for dictation (A05).
  Future<List<SentenceAudio>> sentences();
}

/// A sentence of the packs to hear: its text, lemmas and level, and its
/// clips at normal and slow speed (bucket paths).
typedef SentenceAudio = ({
  String key,
  String text,
  List<String> lemmas,
  CefrLevel level,
  String clip,
  String? slowClip,
});

/// Keys of the learner's own items: `personal:<id>` (docs/10 §7).
const personalKeyPrefix = 'personal:';

class DriftCardContentRepository implements CardContentRepository {
  new(this._db, {this._l2 = 'en'});

  final AppDatabase _db;
  final String _l2;
  final _picker = const CarrierPicker();

  List<ContentItem>? _items;
  Map<String, String>? _contrasts;

  static const _gloss = 'gloss';
  static const _variants = 'variants';
  static const _contrastNote = 'contrast_note';

  static ContentItem _item(ContentItemRow row) => ContentItem(
    key: row.key,
    kind: ItemKind.values.firstWhere((k) => k.code == row.kind),
    level: CefrLevel.values.firstWhere((l) => l.code == row.level),
    lemmas: row.lemmas,
    targets: row.targets,
    grammarCodes: row.grammar,
    text: row.textL2,
    rank: row.rank,
    deprecated: row.deprecated,
  );

  @override
  Future<List<ContentItem>> items() async => _items ??= [
    for (final row in await _db.select(_db.contentItems).get())
      if (ItemKind.values.any((k) => k.code == row.kind) &&
          CefrLevel.values.any((l) => l.code == row.level))
        _item(row),
  ];

  @override
  Future<List<ItemLink>> links() async => [
    for (final row in await _db.select(_db.contentLinks).get())
      if (LinkType.values.any((t) => t.code == row.type))
        ItemLink(
          from: row.fromKey,
          to: row.toKey,
          type: LinkType.values.firstWhere((t) => t.code == row.type),
        ),
  ];

  @override
  Future<PackLanguage?> language() async {
    final pack = await _db.contentDao.targetPack(_l2);
    if (pack == null) return null;
    return PackLanguage(
      rules: switch (pack.manifest) {
        {'normalization': final Map<String, Object?> rules} =>
          NormalizationRules.fromJson(rules),
        _ => const NormalizationRules(version: 0),
      },
      forms: await _db.contentDao.forms(),
      separator: switch (pack.manifest) {
        {'manifest': {'script': {'word_separator': 'none'}}} => '',
        _ => Normalizer.space,
      },
    );
  }

  /// Contrast notes by item key (`contrast_note` rows are keyed `a|b`).
  Future<Map<String, String>> _contrastNotes() async {
    final found = <String, String>{};
    final rows = await (_db.select(
      _db.contentPairEntries,
    )..where((t) => t.kind.equals(_contrastNote))).get();
    for (final row in rows) {
      final note = row.data['note'];
      if (note is! String) continue;
      for (final key in row.key.split('|')) {
        found[key] ??= note;
      }
    }
    return found;
  }

  @override
  Future<List<ContentItem>> personalItems(
    String courseId,
    CefrLevel level,
  ) async {
    final rows =
        await (_db.select(_db.personalItems)..where(
              (t) => t.courseId.equals(courseId) & t.deprecated.equals(false),
            ))
            .get();
    return [
      for (final row in rows)
        if (row.glossL1 != null)
          ContentItem(
            key: '$personalKeyPrefix${row.id}',
            kind: ItemKind.chunk,
            level: CefrLevel.values.firstWhere(
              (l) => l.code == row.cefr,
              orElse: () => level,
            ),
            lemmas: row.lemmas,
            text: row.textL2,
          ),
    ];
  }

  /// A personal item's card: its own words asked with what the learner
  /// wanted to say; the whole sentence is the target.
  Future<CardContent?> _personal(String itemKey) async {
    if (!itemKey.startsWith(personalKeyPrefix)) return null;
    final id = itemKey.substring(personalKeyPrefix.length);
    final row = await (_db.select(
      _db.personalItems,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    final gloss = row?.glossL1;
    if (row == null || gloss == null || row.deprecated) return null;
    final answers = AnswerKey(
      reference: row.textL2,
      targetLemmas: const {},
      variants: row.variants,
    );
    final language = await this.language();
    return CardContent(
      itemKey: itemKey,
      kind: ItemKind.chunk,
      carrierKey: itemKey,
      prompt: gloss,
      answerKey: answers,
      targetSpan: language == null
          ? row.textL2
          : AnswerChecker(language).targetSpan(answers),
      headword: row.textL2,
      meaning: gloss,
      usageNote: row.notes,
    );
  }

  Future<String> _audioPrefix() async {
    final pack = await _db.contentDao.targetPack(_l2);
    return switch (pack?.manifest) {
      {'audio': {'prefix': final String prefix}} => prefix,
      _ => '',
    };
  }

  /// The clip of [speed] in an item's `data.audio`, as a bucket path.
  static String? _clip(Map<String, Object?> data, String prefix, double speed) {
    final clips = data['audio'];
    if (clips is! List<Object?>) return null;
    for (final entry in clips) {
      if (entry case {'speed': final num s, 'file': final String file}
          when s == speed) {
        return '$prefix$file';
      }
    }
    return null;
  }

  @override
  Future<List<SentenceAudio>> sentences() async {
    final prefix = await _audioPrefix();
    final rows = await (_db.select(
      _db.contentItems,
    )..where((t) => t.kind.equals(ItemKind.sentence.code))).get();
    return [
      for (final row in rows)
        if ((row.textL2, _clip(row.data, prefix, 1))
            case (final String text, final String clip)
            when !row.deprecated &&
                CefrLevel.values.any((l) => l.code == row.level))
          (
            key: row.key,
            text: text,
            lemmas: row.lemmas,
            level: CefrLevel.values.firstWhere((l) => l.code == row.level),
            clip: clip,
            slowClip: _clip(row.data, prefix, 0.8),
          ),
    ];
  }

  @override
  Future<CardContent?> content(
    String itemKey, {
    required LemmaKnowledge knowledge,
  }) async {
    final all = await items();
    final byKey = {for (final item in all) item.key: item};
    final item = byKey[itemKey];
    if (item == null) return await _personal(itemKey);
    final row = await _db.contentDao.item(itemKey);
    if (row == null) return null;
    final ContentItem carrier;
    switch (item.kind) {
      case ItemKind.chunk:
        carrier = item;
      case ItemKind.wordSense:
        final keys = switch (row.data['carriers']) {
          final List<Object?> keys => keys.whereType<String>(),
          _ => const <String>[],
        };
        final choices = _picker.pick(
          target: item,
          candidates: [for (final key in keys) ?byKey[key]],
          knowledge: knowledge,
        );
        if (choices.isEmpty) return null;
        carrier = choices.first.carrier;
      case ItemKind.sentence ||
          ItemKind.grammarPoint ||
          ItemKind.sound ||
          ItemKind.pattern:
        return null;
    }
    final reference = carrier.text;
    final carrierRow = await _db.contentDao.item(carrier.key);
    final prompt = await _db.contentDao.pairEntry(_gloss, carrier.key);
    final meaning = await _db.contentDao.pairEntry(_gloss, itemKey);
    if (reference == null ||
        carrierRow == null ||
        prompt?['meaning'] is! String ||
        meaning?['meaning'] is! String) {
      return null;
    }
    final listed = await _db.contentDao.pairEntry(_variants, carrier.key);
    List<String> strings(Object? value) => switch (value) {
      final List<Object?> list => list.whereType<String>().toList(),
      _ => const [],
    };
    final key = AnswerKey(
      reference: reference,
      targetLemmas: item.kind == ItemKind.wordSense ? item.lemmas.toSet() : {},
      variants: strings(listed?['variants']),
      alternatives: strings(listed?['alternatives']),
      answerGrammar: switch (listed?['grammar']) {
        final Map<String, Object?> grammar => {
          for (final MapEntry(:key, :value) in grammar.entries)
            key: strings(value),
        },
        _ => const {},
      },
    );
    final language = await this.language();
    final prefix = await _audioPrefix();
    String? clip(double speed) => _clip(carrierRow.data, prefix, speed);

    final contrasts = _contrasts ??= await _contrastNotes();
    return CardContent(
      itemKey: itemKey,
      kind: item.kind,
      carrierKey: carrier.key,
      prompt: prompt!['meaning']! as String,
      contextNote: prompt['context'] as String?,
      answerKey: key,
      targetSpan: language == null
          ? reference
          : AnswerChecker(language).targetSpan(key),
      grammarCodes: carrier.grammarCodes,
      clip: clip(1),
      slowClip: clip(0.8),
      headword: row.textL2 ?? reference,
      meaning: meaning!['meaning']! as String,
      usageNote: meaning['usage_note'] as String?,
      contrastNote: contrasts[itemKey],
    );
  }
}
