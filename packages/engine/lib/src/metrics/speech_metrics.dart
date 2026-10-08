import 'dart:math';

import 'package:dilbaz_engine/src/language/language_services.dart';
import 'package:dilbaz_engine/src/metrics/mtld.dart';
import 'package:dilbaz_engine/src/metrics/speech_metrics_config.dart';
import 'package:dilbaz_engine/src/speaking/speech_annotation.dart';
import 'package:dilbaz_engine/src/speaking/timed_word.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'speech_metrics.freezed.dart';
part 'speech_metrics.g.dart';

/// Complexity, accuracy and fluency of a recording (docs/06-assessment.md
/// §3.3), as `recordings.metrics` stores it. Everything is computed here
/// from word times and the annotation's marks, never by the model
/// (docs/07 §4.2). A measure without enough data is null: no number is
/// made up (I-04).
///
/// Words are what was said without hesitation sounds: those the pack's
/// normalization lists ("uh") and those the annotation marks.
@freezed
abstract class SpeechMetrics with _$SpeechMetrics {
  /// Creates the measures.
  const factory({
    /// From the first word's start to the last word's end: the silence
    /// before and after is left out.
    required int speakingMs,
    required int words,

    /// Words per minute of speaking time.
    required double speechRate,

    /// Words per minute without the silent pauses.
    required double? articulationRate,

    /// Mean length of run: words between two silent pauses.
    @JsonKey(name: 'mlr') required double? meanLengthOfRun,
    required double longPausesPerMin,

    /// Hesitation sounds of the target language per minute.
    required double filledPausesPerMin,

    /// Silent pauses inside a clause among all silent pauses; a better sign
    /// of low fluency than pauses between clauses.
    required double? midClausePauseRatio,

    /// Hesitation in the learner's own language, per minute. Recognition
    /// in the target language may drop such words: a known limit.
    @JsonKey(name: 'l1_fillers_per_min') required double? l1FillersPerMin,
    required double? repairsPerMin,

    /// Error-free clauses among all clauses.
    @JsonKey(name: 'efc_ratio') required double? efcRatio,
    @JsonKey(name: 'errors_per_100w') required double? errorsPer100Words,

    /// Errors per 100 words by tag.
    required Map<String, double> errorsByTag,
    required double? meanClauseLength,

    /// Clauses per AS-unit.
    required double? subordination,

    /// Lexical diversity; null under the minimum of words.
    required double? mtld,

    /// Different connectors of the pack's list used.
    required int connectorTypes,

    /// Words whose lemma is beyond the frequent ones, among the words with
    /// a known rank.
    @JsonKey(name: 'beyond_2k_share') required double? beyondFrequentShare,
  }) = _SpeechMetrics;

  /// Reads stored measures.
  factory fromJson(Map<String, Object?> json) => _$SpeechMetricsFromJson(json);

  /// The measures of a recording's [words] (in time order). [annotation]
  /// adds those that need clauses, errors and the learner's own fillers;
  /// [connectors] are the pack's list and [rankOf] gives a lemma's
  /// frequency rank. Null when nothing but hesitation was heard.
  static SpeechMetrics? of(
    List<TimedWord> words, {
    required LanguageServices language,
    SpeechAnnotation? annotation,
    Iterable<String> connectors = const [],
    int? Function(String lemma)? rankOf,
    SpeechMetricsConfig config = const SpeechMetricsConfig(),
  }) {
    if (words.isEmpty) return null;
    final speakingMs = words.last.endMs - words.first.startMs;
    if (speakingMs <= 0) return null;
    final marked = {
      for (final filler in annotation?.fillers ?? const <SpokenFiller>[])
        filler.i: filler.kind,
    };
    final kinds = [
      for (final (i, word) in words.indexed)
        marked[i] ?? (language.isFiller(word.text) ? FillerKind.l2 : null),
    ];
    final spoken = [
      for (final (i, kind) in kinds.indexed)
        if (kind == null) i,
    ];
    if (spoken.isEmpty) return null;
    final minutes = speakingMs / Duration.millisecondsPerMinute;

    // The pause after word i, when there is one.
    final pauses = <int>[];
    var silentMs = 0;
    var long = 0;
    for (var i = 0; i + 1 < words.length; i++) {
      final gap = words[i + 1].startMs - words[i].endMs;
      if (gap < config.silentPause.inMilliseconds) continue;
      pauses.add(i);
      silentMs += gap;
      if (gap >= config.longPause.inMilliseconds) long++;
    }
    final runs = <int>[];
    var run = 0;
    for (var i = 0; i < words.length; i++) {
      if (kinds[i] == null) run++;
      final ends = i == words.length - 1 || pauses.contains(i);
      if (!ends) continue;
      if (run > 0) runs.add(run);
      run = 0;
    }
    final phonationMs = speakingMs - silentMs;

    final clauses = annotation?.clauses ?? const <AnnotatedClause>[];
    final errors = annotation?.errors;
    final inSpoken = spoken.toSet();
    final byTag = <String, double>{};
    for (final error in errors ?? const <SpeechError>[]) {
      byTag[error.tag] = (byTag[error.tag] ?? 0) + 100 / spoken.length;
    }
    final tokens = language.tokenize(
      [for (final i in spoken) words[i].text].join(' '),
    );

    return SpeechMetrics(
      speakingMs: speakingMs,
      words: spoken.length,
      speechRate: spoken.length / minutes,
      articulationRate: phonationMs > 0
          ? spoken.length / (phonationMs / Duration.millisecondsPerMinute)
          : null,
      meanLengthOfRun: runs.isEmpty
          ? null
          : runs.reduce((a, b) => a + b) / runs.length,
      longPausesPerMin: long / minutes,
      filledPausesPerMin:
          kinds.where((kind) => kind == FillerKind.l2).length / minutes,
      midClausePauseRatio: clauses.isEmpty || pauses.isEmpty
          ? null
          : pauses
                    .where(
                      (i) => clauses.any((c) => c.startI <= i && i < c.endI),
                    )
                    .length /
                pauses.length,
      l1FillersPerMin: annotation == null
          ? null
          : kinds.where((kind) => kind == FillerKind.l1).length / minutes,
      repairsPerMin: annotation == null
          ? null
          : annotation.repairs.length / minutes,
      efcRatio: clauses.isEmpty
          ? null
          : clauses.where((c) => c.errorFree).length / clauses.length,
      errorsPer100Words: errors == null
          ? null
          : errors.length / spoken.length * 100,
      errorsByTag: byTag,
      meanClauseLength: clauses.isEmpty
          ? null
          : clauses.fold(
                  0,
                  (sum, c) =>
                      sum +
                      [
                        for (var i = c.startI; i <= c.endI; i++)
                          if (inSpoken.contains(i)) i,
                      ].length,
                ) /
                clauses.length,
      subordination: clauses.isEmpty
          ? null
          : clauses.length / {for (final c in clauses) c.asUnit}.length,
      mtld: tokens.length < config.mtldMinWords
          ? null
          : mtld(tokens, threshold: config.mtldThreshold),
      connectorTypes: _connectorTypes(tokens, connectors, language),
      beyondFrequentShare: rankOf == null
          ? null
          : _beyondShare(tokens, language, rankOf, config.frequentRank),
    );
  }

  /// How many of [connectors] occur in [tokens], each counted once.
  static int _connectorTypes(
    List<String> tokens,
    Iterable<String> connectors,
    LanguageServices language,
  ) {
    final phrases = {
      for (final connector in connectors)
        language.tokenize(connector).join(' '),
    }..remove('');
    return phrases.where((phrase) {
      final words = phrase.split(' ');
      for (var i = 0; i + words.length <= tokens.length; i++) {
        var match = true;
        for (var j = 0; j < words.length && match; j++) {
          match = tokens[i + j] == words[j];
        }
        if (match) return true;
      }
      return false;
    }).length;
  }

  /// Share of the ranked [tokens] whose best lemma rank is beyond
  /// [frequent]; null when no token has a rank (names, numbers).
  static double? _beyondShare(
    List<String> tokens,
    LanguageServices language,
    int? Function(String lemma) rankOf,
    int frequent,
  ) {
    var ranked = 0;
    var beyond = 0;
    for (final token in tokens) {
      final ranks = [
        for (final lemma in language.lemmasOf(token)) ?rankOf(lemma),
      ];
      if (ranks.isEmpty) continue;
      ranked++;
      if (ranks.reduce(min) > frequent) beyond++;
    }
    return ranked == 0 ? null : beyond / ranked;
  }
}
