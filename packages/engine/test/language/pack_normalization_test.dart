import 'dart:convert';
import 'dart:io';

import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The target packs' normalization files, as the pack build stores them.
///
/// Their `tests` hold examples that the engine and the content tools must
/// both pass (docs/11-language-packs.md §6). This test reads pack data only
/// as a fixture; the engine's own tests use the synthetic language.
void main() {
  final packs = Directory('../../content/packs');
  final files = [
    for (final dir in packs.listSync().whereType<Directory>())
      if (File('${dir.path}/normalization.yaml').existsSync())
        File('${dir.path}/normalization.yaml'),
  ];

  test('target packs have normalization rules', () {
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    group(file.parent.uri.pathSegments.lastWhere((s) => s.isNotEmpty), () {
      final json = jsonDecode(jsonEncode(loadYaml(file.readAsStringSync())));
      final rules = NormalizationRules.fromJson(json as Map<String, Object?>);
      final normalizer = Normalizer(rules);

      test('has examples', () => expect(rules.tests, isNotEmpty));

      for (final [text, normalized] in rules.tests) {
        test('normalizes "$text"', () {
          expect(normalizer.normalize(text), normalized);
        });
      }
    });
  }
}
