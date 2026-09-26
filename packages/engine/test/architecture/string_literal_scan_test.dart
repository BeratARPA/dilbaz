import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

import 'engine_sources.dart';

/// String literals in lib/ may only be identifiers, keys and codes: ASCII,
/// no whitespace (docs/11-language-packs.md §7.3).
final _identifierLike = RegExp(r'^[A-Za-z0-9_.:/@$|-]*$');

/// Function words of English and Turkish (three letters or more, so that
/// short parameter names such as `at` stay valid). A literal equal to one of
/// these is language data that belongs in a pack, even if it looks like a code.
const _sentinelWords = {
  'the', 'and', 'are', 'was', 'not', 'does', 'did', 'have', 'has', 'you', //
  'she', 'they', 'this', 'that', 'bir', 'ile', 'değil', 'var', 'yok', 'ben',
  'sen',
};

/// Literal values allowed despite the rules above, each with a reason.
const _allowlist = <String>{};

void main() {
  test('lib has no natural-language string literals (I-15)', () {
    final violations = <String>[];
    for (final source in engineLibSources()) {
      final collector = _LiteralCollector();
      source.unit.accept(collector);
      for (final (offset, value) in collector.literals) {
        if (_allowlist.contains(value)) continue;
        if (_identifierLike.hasMatch(value) &&
            !_sentinelWords.contains(value.toLowerCase())) {
          continue;
        }
        final line = source.unit.lineInfo.getLocation(offset).lineNumber;
        violations.add('${source.path}:$line: "$value"');
      }
    }
    expect(violations, isEmpty);
  });

  test('the scan detects prose and function words', () {
    for (final value in [
      'go home',
      'Bir kelime eksik.',
      'Doğru',
      'the',
      'değil',
    ]) {
      final isCode =
          _identifierLike.hasMatch(value) &&
          !_sentinelWords.contains(value.toLowerCase());
      expect(isCode, isFalse, reason: value);
    }
    for (final value in ['utc_required', 'card.produce_speak', 'en@1', '']) {
      expect(_identifierLike.hasMatch(value), isTrue, reason: value);
    }
  });
}

/// Collects string literal values, skipping directive URIs.
final class _LiteralCollector extends RecursiveAstVisitor<void> {
  final literals = <(int, String)>[];

  @override
  void visitImportDirective(ImportDirective node) {}

  @override
  void visitExportDirective(ExportDirective node) {}

  @override
  void visitPartDirective(PartDirective node) {}

  @override
  void visitPartOfDirective(PartOfDirective node) {}

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) =>
      literals.add((node.offset, node.value));

  @override
  void visitInterpolationString(InterpolationString node) =>
      literals.add((node.offset, node.value));
}
