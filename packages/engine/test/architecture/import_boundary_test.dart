import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'engine_sources.dart';

/// Packages the engine may depend on at runtime: pure Dart, no Flutter, IO,
/// network, database or language data (I-15, ADR-0007).
const allowedPackages = {
  'collection',
  'dilbaz_engine',
  'freezed_annotation',
  'fsrs',
  'json_annotation',
  'meta',
};

/// Platform-neutral core libraries (the engine also runs on the web).
const allowedDartLibraries = {
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:math',
  'dart:typed_data',
};

void main() {
  final sources = engineLibSources();

  group('I-15 import boundary', () {
    test('runtime dependencies are allowlisted', () {
      final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
      final dependencies = (pubspec['dependencies'] as Map).keys.cast<String>();
      expect(dependencies, everyElement(isIn(allowedPackages)));
    });

    test('lib imports only neutral core libraries and allowed packages', () {
      final violations = <String>[];
      for (final source in sources) {
        for (final directive in source.unit.directives) {
          if (directive is! NamespaceDirective) continue;
          final uri = directive.uri.stringValue!;
          final ok = switch (Uri.parse(uri)) {
            Uri(scheme: 'dart') => allowedDartLibraries.contains(uri),
            Uri(scheme: 'package', :final pathSegments) =>
              allowedPackages.contains(pathSegments.first),
            Uri(hasScheme: false) =>
              p.posix
                  .normalize(p.posix.join(p.posix.dirname(source.path), uri))
                  .startsWith('lib/'),
            _ => false,
          };
          if (!ok) violations.add('${source.path}: $uri');
        }
      }
      expect(violations, isEmpty);
    });

    test('package:fsrs is imported only in lib/src/fsrs, as fsrs', () {
      final users = <String>[];
      for (final source in sources) {
        for (final directive in source.unit.directives) {
          if (directive is! ImportDirective) continue;
          if (!directive.uri.stringValue!.startsWith('package:fsrs/')) {
            continue;
          }
          users.add(source.path);
          expect(
            source.path,
            startsWith('lib/src/fsrs/'),
            reason: 'FSRS is used only in the fsrs module',
          );
          expect(
            directive.prefix?.name,
            'fsrs',
            reason: '${source.path} must import package:fsrs as fsrs',
          );
        }
      }
      expect(users, isNotEmpty);
    });
  });
}
