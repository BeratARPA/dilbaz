/// A pronunciation problem heard on a word of a shadowed sentence (A07):
/// `index` is the word's place in the sentence, `tag` one of the pair's
/// pronunciation tags, `heard` how the word sounded.
typedef PronIssue = ({int index, String word, String tag, String heard});

/// The problems a shadowed sentence shows, at most [count] (docs/08 §7,
/// ADR-0011: one or two).
///
/// Only tags of the pair's catalog count; their [severity] (how much the
/// problem hurts understanding, docs/02 §6) comes from the pack. The
/// learner's [persistentTags] come first (docs/04 §6), then the more
/// severe, then the tags heard most in this sentence; ties keep the order
/// heard. A tag is shown once.
List<PronIssue> pickPronIssues(
  List<PronIssue> issues, {
  required Map<String, double> severity,
  Set<String> persistentTags = const {},
  int count = 2,
}) {
  final often = <String, int>{};
  for (final issue in issues) {
    often[issue.tag] = (often[issue.tag] ?? 0) + 1;
  }
  final shown = <String>{};
  final candidates =
      [
        for (final (i, issue) in issues.indexed)
          if (severity.containsKey(issue.tag) && shown.add(issue.tag))
            (i, issue),
      ]..sort((a, b) {
        final persistent =
            (persistentTags.contains(b.$2.tag) ? 1 : 0) -
            (persistentTags.contains(a.$2.tag) ? 1 : 0);
        if (persistent != 0) return persistent;
        final severe = severity[b.$2.tag]!.compareTo(severity[a.$2.tag]!);
        if (severe != 0) return severe;
        final frequent = often[b.$2.tag]! - often[a.$2.tag]!;
        if (frequent != 0) return frequent;
        return a.$1 - b.$1;
      });
  return [for (final (_, issue) in candidates.take(count)) issue];
}
