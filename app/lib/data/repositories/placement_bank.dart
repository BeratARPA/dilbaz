import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/daos/content_dao.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';

/// A word of the yes/no vocabulary test; a made-up word has no band.
typedef XlexWord = ({String key, String word, int? band});

/// A sentence with a gap and its choices.
typedef GrammarQuestion = ({
  String key,
  CefrLevel level,
  String stem,
  String answer,
  List<String> distractors,
});

/// A sentence to listen to and write down; `clip` is its path in the
/// `pack-audio` bucket.
typedef DictationSentence = ({
  String key,
  CefrLevel level,
  String text,
  String clip,
});

/// What the device holds of the placement test (docs/06-assessment.md §2):
/// one version of the word list and of the dictation set, and the grammar
/// bank.
final class PlacementBank {
  const new({
    required this.version,
    required this.words,
    required this.vocabLevels,
    required this.grammar,
    required this.dictation,
    required this.language,
  });

  /// The version of the word list and the dictation set (A, B, C).
  final String version;
  final List<XlexWord> words;
  final VocabLevels vocabLevels;

  /// Level → its questions; empty when the pack has no grammar bank.
  final Map<CefrLevel, List<GrammarQuestion>> grammar;

  /// The sentences in the order they are played; empty when the pack has
  /// no dictation set.
  final List<DictationSentence> dictation;

  /// The pack's words and normalization, for scoring what was written.
  final LanguageServices language;
}

/// Reads the placement test from the imported target pack.
class PlacementBankRepository {
  const new(this._content);

  final ContentDao _content;

  static const _xlex = 'xlex';
  static const _grammar = 'placement_grammar';
  static const _dictation = 'placement_dictation';

  /// Whether the pack of [l2] on this device holds a placement test: a
  /// word list and the vocabulary sizes of the levels.
  Stream<bool> watchAvailable(String l2) =>
      _content.watchTargetPack(l2).map((pack) => _vocabLevels(pack) != null);

  /// The test for [l2]. The versions take turns: [taken] is the number of
  /// tests taken before. Null when the pack holds no placement test.
  Future<PlacementBank?> load({required String l2, required int taken}) async {
    final pack = await _content.targetPack(l2);
    final vocabLevels = _vocabLevels(pack);
    if (pack == null || vocabLevels == null) return null;
    final rows = await _content.itemsOfKinds([_xlex, _grammar, _dictation]);
    final versions = {
      for (final row in rows)
        if (row.kind == _xlex) row.data['version']! as String,
    }.toList()..sort();
    if (versions.isEmpty) return null;
    final version = versions[taken % versions.length];

    final grammar = <CefrLevel, List<GrammarQuestion>>{};
    for (final row in rows.where((row) => row.kind == _grammar)) {
      final level = _level(row.level);
      (grammar[level] ??= []).add((
        key: row.key,
        level: level,
        stem: row.textL2!,
        answer: row.data['answer']! as String,
        distractors: (row.data['distractors']! as List<Object?>).cast(),
      ));
    }
    final prefix = switch (pack.manifest) {
      {'audio': {'prefix': final String prefix}} => prefix,
      _ => '',
    };
    final dictation =
        [
          for (final row in rows)
            if (row.kind == _dictation && row.data['version'] == version) row,
        ]..sort(
          (a, b) =>
              (a.data['order']! as int).compareTo(b.data['order']! as int),
        );
    return PlacementBank(
      version: version,
      words: [
        for (final row in rows)
          if (row.kind == _xlex && row.data['version'] == version)
            (key: row.key, word: row.textL2!, band: row.data['band'] as int?),
      ],
      vocabLevels: vocabLevels,
      grammar: grammar,
      dictation: [
        for (final row in dictation)
          if (_clip(row) case final clip?)
            (
              key: row.key,
              level: _level(row.level),
              text: row.textL2!,
              clip: '$prefix$clip',
            ),
      ],
      language: PackLanguage(
        rules: switch (pack.manifest) {
          {'normalization': final Map<String, Object?> rules} =>
            NormalizationRules.fromJson(rules),
          _ => const NormalizationRules(version: 0),
        },
        forms: await _content.forms(),
        separator: switch (pack.manifest) {
          {'manifest': {'script': {'word_separator': 'none'}}} => '',
          _ => Normalizer.space,
        },
      ),
    );
  }

  static VocabLevels? _vocabLevels(
    ContentPackRow? pack,
  ) => switch (pack?.manifest) {
    {'manifest': {'placement': {'vocab_levels': final List<Object?> levels}}} =>
      VocabLevels.fromJson(levels),
    _ => null,
  };

  static CefrLevel _level(String code) =>
      CefrLevel.values.firstWhere((level) => level.code == code);

  /// The clip played for a dictation sentence: the first one at normal
  /// speed.
  static String? _clip(ContentItemRow row) {
    final clips = row.data['audio'];
    if (clips is! List<Object?>) return null;
    for (final clip in clips) {
      if (clip case {'speed': final num speed, 'file': final String file}
          when speed == 1) {
        return file;
      }
    }
    return null;
  }
}
