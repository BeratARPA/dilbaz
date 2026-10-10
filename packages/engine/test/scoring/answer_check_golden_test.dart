import 'dart:convert';
import 'dart:io';

import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The answer_check gold set run through the deterministic check
/// (docs/07-ai-tutor.md §8, ADR-0009 §2): when the LLM is out of reach, a
/// correct or acceptable answer may be called wrong at most 3% of the time,
/// and no hint may give the answer away (I-02).
///
/// The set's answers are ones no listed answer matches, so every case goes
/// through the word alignment. Pack data is read only as a fixture; each
/// case carries the forms of its own words.
void main() {
  final root = Directory('../..');
  final cases = [
    for (final line in File(
      '${root.path}/evals/tutor/answer_check/cases.jsonl',
    ).readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
  ];
  final rules = NormalizationRules.fromJson(
    jsonDecode(
      jsonEncode(
        loadYaml(
          File('${root.path}/content/packs/en/normalization.yaml')
              .readAsStringSync(),
        ),
      ),
    ) as Map<String, Object?>,
  );
  final notes = {
    for (final line in File(
      '${root.path}/content/packs/tr-en/rule_notes.jsonl',
    ).readAsLinesSync())
      if (line.trim().isNotEmpty)
        (jsonDecode(line) as Map<String, Object?>)['code']! as String:
            (jsonDecode(line) as Map<String, Object?>)['note']! as String,
  };

  final results = [for (final c in cases) _Result.of(c, rules)];

  test('the gold set has at least 200 cases', () {
    expect(cases.length, greaterThanOrEqualTo(200));
  });

  test('a correct answer is called wrong at most 3% of the time', () {
    final gold = results.where((r) => r.goldCorrect).toList();
    final missed = gold.where((r) => r.calledWrong).toList();
    final rate = missed.length / gold.length;
    printOnFailure(
      [
        for (final r in missed)
          '${r.id}: ${r.said} -> ${r.check.evaluation.verdict.code}',
      ].join('\n'),
    );
    expect(gold.length, greaterThanOrEqualTo(60));
    expect(rate, lessThanOrEqualTo(0.03));
  });

  test('the target of a minor error is judged as the gold set has it '
      '(ADR-0010)', () {
    final minor = results.where((r) => r.goldMinorTarget != null).toList();
    final differ = [
      for (final r in minor)
        if (r.targetIntact != r.goldMinorTarget) r,
    ];
    printOnFailure(
      [
        for (final r in differ)
          '${r.id}: ${r.said} -> ${r.targetIntact} (${r.goldMinorTarget})',
      ].join('\n'),
    );
    expect(minor.length, greaterThanOrEqualTo(40));
    // 1 of 49 at first: "what time it closes" for "What time does it
    // close?" keeps the target in the gold set.
    expect(differ.length / minor.length, lessThanOrEqualTo(0.05));
  });

  test('templated hints never give the answer away (I-02)', () {
    for (final r in results) {
      final ladder = r.check.ladder;
      if (ladder == null) continue;
      // H2 names a word the learner said.
      final place = ladder.place;
      if (place != null) {
        expect(r.saidWords, contains(place.word), reason: r.id);
      }
      // H3 is the card's own rule note, which must not show the answer.
      final code = ladder.ruleCode;
      if (code == null) continue;
      expect(code, r.ruleCode, reason: r.id);
      final note = notes[code];
      expect(note, isNotNull, reason: '${r.id}: $code has no note');
      expect(
        _leaks(
          note!,
          said: r.saidWords,
          answer: r.normalize(ladder.answer),
          target: r.normalize(r.targetSpan),
          allowed: const [],
          normalize: r.normalize,
        ),
        isFalse,
        reason: '${r.id}: the note of $code gives the answer away',
      );
    }
  });
}

/// One case and its deterministic check.
final class _Result {
  new _({
    required this.id,
    required this.said,
    required this.check,
    required this.targetIntact,
    required this.goldMinorTarget,
    required this.goldCorrect,
    required this.language,
    required this.ruleCode,
    required this.targetSpan,
  });

  factory of(Map<String, Object?> json, NormalizationRules rules) {
    final input = json['input']! as Map<String, Object?>;
    final item = input['item']! as Map<String, Object?>;
    final response = input['response']! as Map<String, Object?>;
    final fixture = json['fixture']! as Map<String, Object?>;
    final expected = json['expected']! as Map<String, Object?>;
    final forms = {
      for (final MapEntry(:key, :value)
          in (fixture['forms']! as Map<String, Object?>).entries)
        key: {for (final lemma in value! as List<Object?>) lemma! as String},
    };
    final language = PackLanguage(rules: rules, forms: forms);
    final ruleCode = fixture['rule_code'] as String?;
    final key = AnswerKey(
      reference: item['reference_l2']! as String,
      targetLemmas: {
        for (final lemma in fixture['target_lemmas']! as List<Object?>)
          lemma! as String,
      },
      variants: [
        for (final text in item['variants']! as List<Object?>) text! as String,
      ],
      alternatives: [
        for (final text in item['alternatives']! as List<Object?>)
          text! as String,
      ],
      ruleCode: ruleCode,
    );
    final said = response['text']! as String;
    final verdicts = {
      for (final v in expected['verdicts']! as List<Object?>) v! as String,
    };
    final checker = AnswerChecker(language);
    return _Result._(
      id: json['id']! as String,
      said: said,
      check: checker.checkWithoutLlm(said, key),
      targetIntact: checker.targetIntact(said, key),
      goldMinorTarget: verdicts.length == 1 && verdicts.single == 'minor_error'
          ? expected['target_ok'] as bool?
          : null,
      goldCorrect: verdicts.every(_correctCodes.contains),
      language: language,
      ruleCode: ruleCode,
      targetSpan: item['target_span']! as String,
    );
  }

  static const _correctCodes = {'correct', 'acceptable_variant'};

  final String id;
  final String said;
  final AnswerCheck check;

  /// The engine's word on the target (ADR-0010).
  final bool targetIntact;

  /// The gold `target_ok` of an answer the gold set calls a minor error
  /// and nothing else; null otherwise, or when the gold leaves it open.
  final bool? goldMinorTarget;

  /// Every verdict the gold set accepts is a correct one.
  final bool goldCorrect;
  final PackLanguage language;
  final String? ruleCode;
  final String targetSpan;

  /// The check counts the answer as a miss for the card.
  bool get calledWrong {
    final evaluation = check.evaluation;
    return switch (evaluation.verdict) {
      Verdict.wrong || Verdict.offTarget => true,
      Verdict.minorError => !evaluation.targetOk,
      _ => false,
    };
  }

  List<String> get saidWords => language.tokenize(said);

  List<String> normalize(String text) => language.tokenize(text);
}

/// The leak check of the tutor function (`_shared/leak.ts`) for a hint of
/// the pack: the whole answer, or a word of it the learner did not say,
/// shown after an arrow ("go → went").
bool _leaks(
  String hint, {
  required List<String> said,
  required List<String> answer,
  required List<String> target,
  required List<String> allowed,
  required List<String> Function(String) normalize,
}) {
  final shown = normalize(hint);
  if (answer.length >= 2 && _containsRun(shown, answer)) return true;
  final forms = [
    for (final match in RegExp('→([^,.;:()]*)').allMatches(hint))
      ...normalize(match.group(1)!),
  ];
  final fixes = {...target, ...answer}.where(
    (word) =>
        word.length >= 2 && !said.contains(word) && !allowed.contains(word),
  );
  return fixes.any(forms.contains);
}

bool _containsRun(List<String> haystack, List<String> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var all = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        all = false;
        break;
      }
    }
    if (all) return true;
  }
  return false;
}
