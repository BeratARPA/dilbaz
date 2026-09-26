import 'dart:math';

import 'package:dilbaz_engine/dilbaz_engine.dart';

/// Synthetic target language "zz" used by every engine test (I-15).
///
/// Words are random syllable strings that include non-ASCII letters, forms
/// come from synthetic suffixes plus suppletive and homograph forms, and
/// grammar codes are opaque. Any English-specific assumption in the engine
/// (spaces, "the", ASCII) therefore breaks these tests. Generation is seeded
/// and reproducible (docs/15-testing.md §3).
final class ZzPack {
  new _({
    required this.seed,
    required this.wordSeparator,
    required this.lexicon,
    required this.forms,
    required this.items,
    required this.links,
  });

  /// Generates a pack; the same arguments always give the same pack.
  factory generate({
    int seed = 1,
    int lemmaCount = 400,
    int sentenceCount = 300,
    String wordSeparator = ' ',
  }) => _ZzGenerator(
    seed: seed,
    lemmaCount: lemmaCount,
    sentenceCount: sentenceCount,
    wordSeparator: wordSeparator,
  ).build();

  /// Language code of the synthetic target language.
  static const l2 = 'zz';

  /// Sentence-final punctuation marks used in sentence texts.
  static const punctuation = ['.', '?', '!'];

  /// Seed the pack was generated from.
  final int seed;

  /// Separator between words in sentence and chunk texts.
  final String wordSeparator;

  /// Lemmas ordered by frequency rank.
  final List<LexiconEntry> lexicon;

  /// Surface form → lemmas (the pack's `forms` table), lowercase.
  final Map<String, Set<String>> forms;

  /// Word senses, chunks, grammar points and sentences.
  final List<ContentItem> items;

  /// Curriculum graph edges.
  final List<ItemLink> links;

  /// Grammar codes (closed list), in level order.
  List<String> get grammarCodes => [
    for (final item in ofKind(ItemKind.grammarPoint)) item.key,
  ];

  /// Items of one kind, in generation order.
  List<ContentItem> ofKind(ItemKind kind) => [
    for (final item in items)
      if (item.kind == kind) item,
  ];

  /// The item with [key]; throws if absent.
  ContentItem item(String key) => items.firstWhere((i) => i.key == key);

  /// The lexicon entry of [lemma]; throws if absent.
  LexiconEntry entry(String lemma) =>
      lexicon.firstWhere((e) => e.lemma == lemma);
}

final class _ZzGenerator {
  new({
    required this.seed,
    required this.lemmaCount,
    required this.sentenceCount,
    required this.wordSeparator,
  }) : _random = Random(seed);

  final int seed;
  final int lemmaCount;
  final int sentenceCount;
  final String wordSeparator;
  final Random _random;

  static final List<String> _onsets = 'p t k b d g m n l r s v z ʒ'.split(' ');
  static final List<String> _vowels = 'a e i o u ø å'.split(' ');
  static final List<String> _codas = ',,,n,l,r,s,k'.split(',');

  /// Part-of-speech distribution (Universal Dependencies tags).
  static const _posWeights = {
    'NOUN': 8,
    'VERB': 5,
    'ADJ': 3,
    'ADV': 1,
    'PRON': 1,
    'ADP': 1,
    'DET': 1,
  };

  /// Upper rank fraction of each level band.
  static const List<(double, CefrLevel)> _levelBands = [
    (0.05, CefrLevel.a0),
    (0.20, CefrLevel.a1),
    (0.40, CefrLevel.a2),
    (0.60, CefrLevel.b1),
    (0.75, CefrLevel.b2),
    (0.90, CefrLevel.c1),
    (1.00, CefrLevel.c2),
  ];

  /// Regular inflection suffixes per part of speech.
  static const _suffixes = {
    'VERB': ['ta', 'mi', 'lo'],
    'NOUN': ['ven'],
    'ADJ': ['ri'],
  };

  static const _senseTags = {
    'NOUN': 'n',
    'VERB': 'v',
    'ADJ': 'adj',
    'ADV': 'adv',
  };

  static const _grammarPointCount = 20;
  static const _chunkCount = 40;
  static const _contrastCount = 15;
  static const _homographCount = 3;

  final _used = <String>{};

  ZzPack build() {
    final lexicon = _buildLexicon();
    final forms = _buildForms(lexicon);
    final grammarPoints = _buildGrammarPoints();
    final senses = _buildWordSenses(lexicon);
    final links = <ItemLink>[];
    final chunks = _buildChunks(lexicon, senses, links);
    _addContrasts(senses, links);
    final sentences = _buildSentences(
      lexicon: lexicon,
      forms: forms,
      targets: [...senses, ...chunks],
      grammarPoints: grammarPoints,
      links: links,
    );
    return ZzPack._(
      seed: seed,
      wordSeparator: wordSeparator,
      lexicon: lexicon,
      forms: forms,
      items: [...grammarPoints, ...senses, ...chunks, ...sentences],
      links: links,
    );
  }

  List<LexiconEntry> _buildLexicon() {
    final posPool = [
      for (final MapEntry(:key, :value) in _posWeights.entries)
        for (var i = 0; i < value; i++) key,
    ];
    return [
      for (var rank = 1; rank <= lemmaCount; rank++)
        LexiconEntry(
          lemma: _freshWord(),
          rank: rank,
          level: _levelForRank(rank),
          pos: posPool[_random.nextInt(posPool.length)],
        ),
    ];
  }

  CefrLevel _levelForRank(int rank) {
    final fraction = rank / lemmaCount;
    return _levelBands.firstWhere((band) => fraction <= band.$1).$2;
  }

  Map<String, Set<String>> _buildForms(List<LexiconEntry> lexicon) {
    final forms = <String, Set<String>>{};
    void add(String surface, String lemma) =>
        (forms[surface] ??= <String>{}).add(lemma);

    final nouns = [
      for (final e in lexicon)
        if (e.pos == 'NOUN') e.lemma,
    ];
    var homographs = 0;
    var verbIndex = 0;
    for (final entry in lexicon) {
      add(entry.lemma, entry.lemma);
      final suffixes = _suffixes[entry.pos] ?? const <String>[];
      for (final (i, suffix) in suffixes.indexed) {
        final isPast = entry.pos == 'VERB' && i == 0;
        if (isPast && verbIndex++ % 16 == 0) {
          // Suppletive past form; the first few are homographs of a noun.
          final surface = homographs < _homographCount
              ? nouns[homographs++]
              : _freshWord();
          add(surface, entry.lemma);
        } else {
          final surface = '${entry.lemma}$suffix';
          _used.add(surface);
          add(surface, entry.lemma);
        }
      }
    }
    return forms;
  }

  List<ContentItem> _buildGrammarPoints() {
    const levels = [
      CefrLevel.a0,
      CefrLevel.a1,
      CefrLevel.a2,
      CefrLevel.b1,
      CefrLevel.b2,
    ];
    return [
      for (var i = 0; i < _grammarPointCount; i++)
        ContentItem(
          key: 'gp.${ZzPack.l2}.g${(i + 1).toString().padLeft(2, '0')}',
          kind: ItemKind.grammarPoint,
          level: levels[i * levels.length ~/ _grammarPointCount],
        ),
    ];
  }

  List<ContentItem> _buildWordSenses(List<LexiconEntry> lexicon) {
    final senses = <ContentItem>[];
    for (final entry in lexicon) {
      final tag = _senseTags[entry.pos];
      if (tag == null) continue;
      ContentItem sense(int n, CefrLevel level) => ContentItem(
        key: '${ZzPack.l2}.ws.${entry.lemma}.$tag.$n',
        kind: ItemKind.wordSense,
        level: level,
        lemmas: [entry.lemma],
        text: entry.lemma,
        rank: entry.rank,
      );
      senses.add(sense(1, entry.level));
      if (_random.nextInt(10) == 0) {
        final next =
            CefrLevel.values[min(entry.level.scale + 1, CefrLevel.c2.scale)];
        senses.add(sense(2, next));
      }
    }
    return senses;
  }

  List<ContentItem> _buildChunks(
    List<LexiconEntry> lexicon,
    List<ContentItem> senses,
    List<ItemLink> links,
  ) {
    List<LexiconEntry> upToB1(String pos) => [
      for (final e in lexicon)
        if (e.pos == pos && e.level.isAtMost(CefrLevel.b1)) e,
    ];
    String firstSense(String lemma) =>
        senses.firstWhere((s) => s.lemmas.single == lemma).key;

    final verbs = upToB1('VERB');
    final nouns = upToB1('NOUN');
    final chunks = <ContentItem>[];
    final keys = <String>{};
    while (chunks.length < _chunkCount) {
      final verb = verbs[_random.nextInt(verbs.length)];
      final noun = nouns[_random.nextInt(nouns.length)];
      final key = '${ZzPack.l2}.chunk.${verb.lemma}_${noun.lemma}';
      if (!keys.add(key)) continue;
      final level = verb.level.scale >= noun.level.scale
          ? verb.level
          : noun.level;
      chunks.add(
        ContentItem(
          key: key,
          kind: ItemKind.chunk,
          level: level,
          lemmas: [verb.lemma, noun.lemma],
          text: '${verb.lemma}$wordSeparator${noun.lemma}',
        ),
      );
      final verbSense = firstSense(verb.lemma);
      links
        ..add(ItemLink(from: key, to: verbSense, type: LinkType.contains))
        ..add(
          ItemLink(
            from: key,
            to: firstSense(noun.lemma),
            type: LinkType.contains,
          ),
        );
      if (chunks.length.isEven) {
        links.add(ItemLink(from: key, to: verbSense, type: LinkType.requires));
      }
    }
    return chunks;
  }

  void _addContrasts(List<ContentItem> senses, List<ItemLink> links) {
    final pairs = <String>{};
    var added = 0;
    while (added < _contrastCount) {
      final a = senses[_random.nextInt(senses.length)];
      final b = senses[_random.nextInt(senses.length)];
      final sameTag = a.key.split('.')[3] == b.key.split('.')[3];
      final close = (a.level.scale - b.level.scale).abs() <= 1;
      if (a.key == b.key || !sameTag || !close) continue;
      final pairKey = ([a.key, b.key]..sort()).join('|');
      if (!pairs.add(pairKey)) continue;
      links.add(ItemLink(from: a.key, to: b.key, type: LinkType.contrastsWith));
      added++;
    }
  }

  List<ContentItem> _buildSentences({
    required List<LexiconEntry> lexicon,
    required Map<String, Set<String>> forms,
    required List<ContentItem> targets,
    required List<ContentItem> grammarPoints,
    required List<ItemLink> links,
  }) {
    final formsOf = <String, List<String>>{};
    for (final MapEntry(key: surface, value: lemmas) in forms.entries) {
      for (final lemma in lemmas) {
        (formsOf[lemma] ??= <String>[]).add(surface);
      }
    }
    String surfaceOf(String lemma) {
      final options = formsOf[lemma]!;
      return options[_random.nextInt(options.length)];
    }

    final sentences = <ContentItem>[];
    for (var i = 0; i < sentenceCount; i++) {
      final target = targets[_random.nextInt(targets.length)];
      final level = target.level;
      final pool = [
        for (final e in lexicon)
          if (e.level.isAtMost(level) && !target.lemmas.contains(e.lemma))
            e.lemma,
      ];
      final others = <String>[];
      final wanted = 2 + _random.nextInt(4);
      while (others.length < wanted && others.length < pool.length) {
        final lemma = pool[_random.nextInt(pool.length)];
        if (!others.contains(lemma)) others.add(lemma);
      }
      final words = [for (final lemma in others) surfaceOf(lemma)];
      final targetWords = [for (final lemma in target.lemmas) surfaceOf(lemma)];
      words.insertAll(_random.nextInt(words.length + 1), targetWords);
      words[0] = _capitalized(words[0]);
      final punctuation =
          ZzPack.punctuation[_random.nextInt(ZzPack.punctuation.length)];

      final lemmas = <String>[];
      for (final lemma in [...target.lemmas, ...others]) {
        if (!lemmas.contains(lemma)) lemmas.add(lemma);
      }
      final grammar = <String>{};
      for (var g = _random.nextInt(3); g > 0; g--) {
        final code = _pickGrammarCode(grammarPoints, level);
        if (code != null) grammar.add(code);
      }

      final key = '${ZzPack.l2}.sent.${(i + 1).toString().padLeft(4, '0')}';
      sentences.add(
        ContentItem(
          key: key,
          kind: ItemKind.sentence,
          level: level,
          lemmas: lemmas,
          targets: [target.key],
          grammarCodes: grammar.toList(),
          text: '${words.join(wordSeparator)}$punctuation',
        ),
      );
      links.add(ItemLink(from: key, to: target.key, type: LinkType.contains));
      for (final code in grammar) {
        links.add(ItemLink(from: key, to: code, type: LinkType.exampleOf));
      }
    }
    return sentences;
  }

  String? _pickGrammarCode(List<ContentItem> grammarPoints, CefrLevel level) {
    final allowed = [
      for (final g in grammarPoints)
        if (g.level.isAtMost(level)) g.key,
    ];
    return allowed.isEmpty ? null : allowed[_random.nextInt(allowed.length)];
  }

  String _freshWord() {
    while (true) {
      final syllables = 1 + _random.nextInt(3);
      final buffer = StringBuffer();
      for (var s = 0; s < syllables; s++) {
        buffer
          ..write(_onsets[_random.nextInt(_onsets.length)])
          ..write(_vowels[_random.nextInt(_vowels.length)])
          ..write(_codas[_random.nextInt(_codas.length)]);
      }
      final word = buffer.toString();
      if (word.length >= 3 && _isFree(word)) {
        _used.add(word);
        return word;
      }
    }
  }

  /// A new word must not collide with any word or with a regular form of it.
  bool _isFree(String word) {
    if (_used.contains(word)) return false;
    for (final suffixes in _suffixes.values) {
      for (final suffix in suffixes) {
        if (_used.contains('$word$suffix')) return false;
      }
    }
    return !_used.any(
      (w) => _suffixes.values.any((s) => s.any((x) => word == '$w$x')),
    );
  }

  static String _capitalized(String word) =>
      '${word.substring(0, 1).toUpperCase()}${word.substring(1)}';
}
