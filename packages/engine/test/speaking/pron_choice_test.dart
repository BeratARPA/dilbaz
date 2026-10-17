import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

PronIssue heard(int index, String tag) =>
    (index: index, word: 'w$index', tag: tag, heard: 'h$index');

const severity = {'zz.a': 0.4, 'zz.b': 0.3, 'zz.c': 0.3, 'zz.d': 0.2};

void main() {
  test('the more severe first, a tag once, at most two', () {
    final picked = pickPronIssues([
      heard(0, 'zz.d'),
      heard(1, 'zz.b'),
      heard(2, 'zz.a'),
      heard(3, 'zz.a'),
    ], severity: severity);
    expect(picked.map((i) => (i.index, i.tag)), [(2, 'zz.a'), (1, 'zz.b')]);
  });

  test('persistent tags first; then the tag heard most; then the order', () {
    final issues = [
      heard(0, 'zz.b'),
      heard(1, 'zz.c'),
      heard(2, 'zz.c'),
      heard(3, 'zz.d'),
    ];
    expect(
      pickPronIssues(
        issues,
        severity: severity,
        persistentTags: {'zz.d'},
      ).map((i) => i.tag),
      ['zz.d', 'zz.c'],
    );
    expect(
      pickPronIssues(
        [heard(0, 'zz.b'), heard(1, 'zz.c')],
        severity: severity,
        count: 1,
      ).single.tag,
      'zz.b',
    );
  });

  test('a tag outside the catalog is not shown (I-11)', () {
    expect(pickPronIssues([heard(0, 'zz.x')], severity: severity), isEmpty);
    expect(pickPronIssues(const [], severity: severity), isEmpty);
  });
}
