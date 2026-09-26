import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

/// A hand-written library file of the engine and its parsed AST.
typedef EngineSource = ({String path, CompilationUnit unit});

/// Hand-written Dart files under `lib/` (generated parts are excluded).
///
/// Paths are relative to the package root and use `/` separators.
List<EngineSource> engineLibSources() {
  final files =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => p.posix.joinAll(p.split(f.path)))
          .where(
            (path) =>
                path.endsWith('.dart') &&
                !path.endsWith('.g.dart') &&
                !path.endsWith('.freezed.dart'),
          )
          .toList()
        ..sort();
  return [
    for (final path in files)
      (
        path: path,
        unit: parseFile(
          path: p.normalize(p.absolute(path)),
          featureSet: FeatureSet.latestLanguageVersion(),
        ).unit,
      ),
  ];
}
