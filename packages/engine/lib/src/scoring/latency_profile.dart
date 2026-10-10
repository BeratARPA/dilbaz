/// The learner's recent answer latencies in one card mode: the reference
/// for an Easy rating (docs/03-activities.md §0.3).
final class LatencyProfile {
  /// Profile of [recentMs], newest first; only the newest [window] count.
  factory of(Iterable<int> recentMs) {
    final sample = recentMs.take(window).toList();
    for (final ms in sample) {
      if (ms < 0) throw ArgumentError.value(ms, 'recentMs', 'negative');
    }
    return LatencyProfile._(_percentile(sample));
  }

  const new _(this.easyBelowMs);

  /// No history yet: no answer counts as fast.
  static const none = LatencyProfile._(null);

  /// Latest attempts that form the reference.
  static const window = 200;

  /// Fewer latencies than this give no Easy rating.
  static const minSamples = 20;

  /// Share of recent answers an Easy answer must beat (25th percentile).
  static const fastShare = 0.25;

  /// Answers faster than this are fast; null with too little history.
  final double? easyBelowMs;

  /// Whether an answer after [latencyMs] was fast for this learner.
  bool isFast(int latencyMs) {
    final threshold = easyBelowMs;
    return threshold != null && latencyMs < threshold;
  }

  /// Linear interpolation between the closest ranks.
  static double? _percentile(List<int> sample) {
    if (sample.length < minSamples) return null;
    final sorted = [...sample]..sort();
    final rank = (sorted.length - 1) * fastShare;
    final lower = sorted[rank.floor()];
    final upper = sorted[rank.ceil()];
    return lower + (upper - lower) * (rank - rank.floor());
  }
}
