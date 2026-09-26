import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Forbidden words (docs/09-ux-motivation.md §2, I-12).
///
/// Single words match as word prefixes because Turkish adds suffixes
/// ("seriyi", "başarısızlık"). Phrases and marks match as substrings.
const forbiddenWordStems = [
  'kaçırdın',
  'kaçırıldı',
  'seri',
  'başarısız',
  'uyarı',
  'tembel',
  'ceza',
  'yapmalısın',
  'zorunlu',
];
const forbiddenPhrases = ['dikkat!', 'geride kaldın'];

/// Lowercases with Turkish dotted/dotless i rules.
String turkishLower(String text) =>
    text.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Forbidden stems and phrases found in [text].
List<String> forbiddenIn(String text) {
  final lower = turkishLower(text);
  final words = RegExp(
    r'\p{L}+',
    unicode: true,
  ).allMatches(lower).map((m) => m[0]!).toList();
  return [
    for (final stem in forbiddenWordStems)
      if (words.any((word) => word.startsWith(stem))) stem,
    for (final phrase in forbiddenPhrases)
      if (lower.contains(phrase)) phrase,
  ];
}

void main() {
  final arbFiles =
      Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('there is at least one ARB file', () {
    expect(arbFiles, isNotEmpty);
  });

  for (final file in arbFiles) {
    test('${file.path} has no forbidden words (I-12)', () {
      final arb = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final violations = [
        for (final MapEntry(:key, :value) in arb.entries)
          if (!key.startsWith('@') && value is String)
            for (final found in forbiddenIn(value)) '$key: $found',
      ];
      expect(violations, isEmpty);
    });
  }

  test('the check catches inflected, uppercase and phrase forms', () {
    expect(forbiddenIn('Seriyi koru!'), ['seri']);
    expect(forbiddenIn('DİKKAT! Süre doluyor'), ['dikkat!']);
    expect(forbiddenIn('Geride kaldın.'), ['geride kaldın']);
    expect(forbiddenIn('Bu bir başarısızlık değil'), ['başarısız']);
    expect(forbiddenIn('KAÇIRDIN'), ['kaçırdın']);
    expect(forbiddenIn('Bugün 18 kart tekrarladın.'), isEmpty);
    expect(forbiddenIn('Neredeyse. Bir kelime eksik.'), isEmpty);
  });
}
