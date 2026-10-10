import 'package:dilbaz_engine/src/language/language_services.dart';
import 'package:dilbaz_engine/src/language/normalizer.dart';
import 'package:dilbaz_engine/src/language/word_alignment.dart';
import 'package:dilbaz_engine/src/language/word_diff.dart';
import 'package:dilbaz_engine/src/scoring/answer_check.dart';
import 'package:dilbaz_engine/src/scoring/answer_key.dart';
import 'package:dilbaz_engine/src/scoring/evaluation.dart';
import 'package:dilbaz_engine/src/scoring/hint_kind.dart';
import 'package:dilbaz_engine/src/scoring/hint_ladder.dart';
import 'package:dilbaz_engine/src/scoring/hint_place.dart';
import 'package:dilbaz_engine/src/scoring/verdict.dart';

/// The deterministic answer check (docs/03-activities.md §0.5).
///
/// [match] runs before any LLM call: a normalized answer equal to a known
/// correct answer is correct, with or without the card's target.
/// [checkWithoutLlm] adds step 4 for when the LLM is out of reach: the
/// answer is aligned word by word with the nearest correct answer that
/// says the target.
final class AnswerChecker {
  /// A checker for one target language.
  new(this.language);

  /// From this many words on, two differences still count as small;
  /// shorter answers allow one.
  static const longAnswer = 6;

  /// An answer that misses the target by far, but keeps at least one in
  /// this many words of the correct answer and is more than a fragment of
  /// it, may say the same thing another way: undecided rather than off
  /// target.
  static const paraphraseKeepsOneIn = 3;

  /// The target language's services.
  final LanguageServices language;

  /// Step 2: an exact match after normalization; null when the answer
  /// matches nothing and the LLM must decide.
  Evaluation? match(String answer, AnswerKey key) {
    final said = language.normalize(answer);
    if (said.isEmpty) {
      return const Evaluation(verdict: Verdict.unintelligible, targetOk: false);
    }
    for (final (:text, :withTarget) in _answers(key)) {
      if (language.normalize(text) != said) continue;
      return withTarget
          ? const Evaluation(verdict: Verdict.correct, targetOk: true)
          : const Evaluation(
              verdict: Verdict.acceptableVariant,
              targetOk: false,
            );
    }
    return null;
  }

  /// Steps 2 and 4: [match], else a word alignment with the nearest
  /// correct answer that says the target.
  AnswerCheck checkWithoutLlm(String answer, AnswerKey key) {
    final matched = match(answer, key);
    if (matched != null) return AnswerCheck(evaluation: matched);
    return _judgement(answer, key).check();
  }

  /// Whether [answer] keeps the card's target intact: every target word is
  /// there, in the right form and place, next to the nearest correct answer
  /// that says the target. On a grammar card the whole answer is the
  /// target. It settles the LLM's minor error (`Evaluation.settled`,
  /// ADR-0010).
  bool targetIntact(String answer, AnswerKey key) =>
      match(answer, key)?.targetOk ?? _judgement(answer, key).targetIntact;

  /// Step 4's alignment of [answer] with the nearest correct answer that
  /// says the target.
  _Judgement _judgement(String answer, AnswerKey key) {
    final said = language.tokenize(answer);
    late WordAlignment nearest;
    late String nearestText;
    for (final (:text, :withTarget) in _answers(key)) {
      if (!withTarget) continue;
      final alignment = WordAlignment.of(
        language.tokenize(text),
        said,
        sameLemma: _sameLemma,
      );
      if (identical(text, key.reference) ||
          alignment.diffs.length < nearest.diffs.length) {
        nearest = alignment;
        nearestText = text;
      }
    }
    return _Judgement(nearest, nearestText, key, language);
  }

  /// The words of the reference that carry the card's target, normalized:
  /// what the LLM is told the card practises (docs/07 §4.1). The whole
  /// reference when none of its words is a form of a target lemma.
  String targetSpan(AnswerKey key) {
    final lemmas = key.targetLemmas;
    final found = [
      for (final word in language.tokenize(key.reference))
        if (language.lemmasOf(word).any(lemmas.contains)) word,
    ];
    return found.isEmpty ? key.reference : found.join(Normalizer.space);
  }

  /// The key's listed answers split by this card's target: those that say
  /// it and those that do not (docs/07 §4.1). The LLM gets them so.
  ({List<String> withTarget, List<String> withoutTarget}) listed(
    AnswerKey key,
  ) {
    final answers = _answers(key).skip(1).toList();
    return (
      withTarget: [
        for (final (:text, :withTarget) in answers)
          if (withTarget) text,
      ],
      withoutTarget: [
        for (final (:text, :withTarget) in answers)
          if (!withTarget) text,
      ],
    );
  }

  /// The key's correct answers, the reference first, each with whether it
  /// says this card's target.
  ///
  /// The packs list variants and alternatives per sentence, for the items
  /// the sentence was chosen to carry. A sentence carries other items too,
  /// so what counts is whether the card's own target is in the text: the
  /// target's words on a word card, the card's structure on a grammar card
  /// (the pack's grammar codes of each answer). When the target cannot be
  /// found even in the reference, or an answer's structure is not known,
  /// the lists decide.
  Iterable<({String text, bool withTarget})> _answers(AnswerKey key) sync* {
    yield (text: key.reference, withTarget: true);
    final lemmas = key.targetLemmas;
    final code = key.ruleCode;
    if (lemmas.isEmpty && code != null) {
      bool? uses(String text) => key.answerGrammar[text]?.contains(code);
      for (final text in key.variants) {
        yield (text: text, withTarget: uses(text) ?? true);
      }
      for (final text in key.alternatives) {
        yield (text: text, withTarget: uses(text) ?? false);
      }
      return;
    }
    final known = lemmas.isNotEmpty && _says(key.reference, lemmas);
    for (final text in key.variants) {
      yield (text: text, withTarget: !known || _says(text, lemmas));
    }
    for (final text in key.alternatives) {
      yield (text: text, withTarget: known && _says(text, lemmas));
    }
  }

  bool _says(String text, Set<String> lemmas) =>
      {for (final word in language.tokenize(text)) ...language.lemmasOf(word)}
          .containsAll(lemmas);

  bool _sameLemma(String expected, String actual) =>
      language.lemmasOf(expected).any(language.lemmasOf(actual).contains);
}

/// State of the target part in an answer.
enum _Target {
  /// Every target word is there, in the right form and place.
  intact,

  /// Target words are there, but in another form or order, or split.
  damaged,

  /// A target word is missing.
  omitted,

  /// Another word stands where a target word should.
  replaced,
}

/// Step 4 for one alignment.
final class _Judgement {
  new(this.alignment, this.answerText, this.key, LanguageServices language)
    : target = _targetOf(alignment.expected, key.targetLemmas, language);

  final WordAlignment alignment;
  final String answerText;
  final AnswerKey key;

  /// Indices of the target words in the expected text.
  final Set<int> target;

  static Set<int> _targetOf(
    List<String> words,
    Set<String> lemmas,
    LanguageServices language,
  ) {
    final found = {
      for (final (i, word) in words.indexed)
        if (language.lemmasOf(word).any(lemmas.contains)) i,
    };
    // Without a known target word, the whole answer is the target.
    return found.isEmpty ? {for (var i = 0; i < words.length; i++) i} : found;
  }

  /// Every target word is there, in the right form and place.
  bool get targetIntact =>
      _state(alignment.diffs.where(_touchesTarget).toList()) == _Target.intact;

  AnswerCheck check() {
    final diffs = alignment.diffs;
    final onTarget = diffs.where(_touchesTarget).toList();
    final state = _state(onTarget);
    final long = alignment.expected.length >= AnswerChecker.longAnswer;
    final small = diffs.length <= (long ? 2 : 1);
    switch (state) {
      case _Target.intact:
        if (diffs.isEmpty) return _verdict(Verdict.correct, targetOk: true);
        final classifiable = diffs.every((d) => d.kind != WordDiffKind.other);
        return small && classifiable
            ? _verdict(Verdict.minorError, targetOk: true)
            : _undecided(targetOk: true);
      case _Target.damaged:
        final formOnly = onTarget.every((d) => d.kind == WordDiffKind.form);
        return _miss(
          formOnly ? Verdict.minorError : Verdict.wrong,
          onTarget.first,
        );
      case _Target.omitted:
        return small
            ? _miss(
                Verdict.wrong,
                onTarget.firstWhere((d) => d.kind == WordDiffKind.missing),
              )
            : _farMiss();
      case _Target.replaced:
        // Small: perhaps a synonym, which only the LLM can tell.
        return small ? _undecided(targetOk: false) : _farMiss();
    }
  }

  bool _touchesTarget(WordDiff diff) {
    if (diff.expected.any(target.contains)) return true;
    final before = diff.before;
    if (before == null || target.isEmpty) return false;
    // An extra word inside the target splits it.
    final first = target.reduce((a, b) => a < b ? a : b);
    final last = target.reduce((a, b) => a > b ? a : b);
    return before > first && before <= last;
  }

  static _Target _state(List<WordDiff> onTarget) {
    bool any(WordDiffKind kind) => onTarget.any((d) => d.kind == kind);
    if (any(WordDiffKind.other)) return _Target.replaced;
    if (any(WordDiffKind.missing)) return _Target.omitted;
    return onTarget.isEmpty ? _Target.intact : _Target.damaged;
  }

  AnswerCheck _verdict(Verdict verdict, {required bool targetOk}) =>
      AnswerCheck(
        evaluation: Evaluation(verdict: verdict, targetOk: targetOk),
      );

  AnswerCheck _undecided({required bool targetOk}) => AnswerCheck(
    evaluation: Evaluation(
      verdict: Verdict.uncertain,
      targetOk: targetOk,
      llmPending: true,
    ),
  );

  /// A big miss of the target: off target, unless the answer keeps enough
  /// of the correct answer and changes more than leaving words out, so that
  /// it may say the same thing without the target ("Remember to buy
  /// bread!" for "Don't forget to buy bread!"). A fragment only leaves out.
  AnswerCheck _farMiss() {
    final replaced = {
      for (final diff in alignment.diffs)
        if (diff.kind == WordDiffKind.other) ...diff.expected,
    };
    final kept = alignment.aligned.keys.where((e) => !replaced.contains(e));
    final fragment = alignment.diffs.every(
      (d) => d.kind == WordDiffKind.missing,
    );
    return !fragment &&
            kept.length * AnswerChecker.paraphraseKeepsOneIn >=
                alignment.expected.length
        ? _undecided(targetOk: false)
        : _offTarget();
  }

  AnswerCheck _offTarget() => AnswerCheck(
    evaluation: const Evaluation(verdict: Verdict.offTarget, targetOk: false),
    ladder: HintLadder(
      kind: HintKind.meaning,
      answer: answerText,
      ruleCode: key.ruleCode,
    ),
  );

  AnswerCheck _miss(Verdict verdict, WordDiff focus) => AnswerCheck(
    evaluation: Evaluation(verdict: verdict, targetOk: false),
    ladder: HintLadder(
      kind: switch (focus.kind) {
        WordDiffKind.missing => HintKind.missingWord,
        WordDiffKind.extra => HintKind.extraWord,
        WordDiffKind.form || WordDiffKind.other => HintKind.wrongForm,
        WordDiffKind.order => HintKind.wordOrder,
      },
      answer: answerText,
      place: _place(focus),
      ruleCode: key.ruleCode,
    ),
  );

  /// Where [diff] is, told with a word of the learner's answer.
  HintPlace _place(WordDiff diff) {
    final words = alignment.actual;
    if (diff.actual.isNotEmpty) {
      final index = diff.actual.first;
      return HintPlace(
        relation: HintRelation.at,
        word: words[index],
        index: index,
      );
    }
    // A missing word: before the next word the learner said, else after
    // the previous one. A non-empty answer always has an aligned word.
    final missing = diff.expected.first;
    final aligned = alignment.aligned;
    final later = [
      for (var e = missing + 1; e < alignment.expected.length; e++) ?aligned[e],
    ];
    if (later.isNotEmpty) {
      return HintPlace(
        relation: HintRelation.before,
        word: words[later.first],
        index: later.first,
      );
    }
    final earlier = [for (var e = 0; e < missing; e++) ?aligned[e]];
    return HintPlace(
      relation: HintRelation.after,
      word: words[earlier.last],
      index: earlier.last,
    );
  }
}
