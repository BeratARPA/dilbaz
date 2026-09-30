import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';

/// A level estimate as the learner reads it: one level, a range, or a
/// level with no upper end the test could reach (I-04).
String levelText(AppLocalizations l10n, LevelEstimate estimate) {
  final low = estimate.reached;
  final high = estimate.ceiling;
  if (low == high) return low.code;
  if (high == CefrLevel.values.last) return l10n.levelAndAbove(low.code);
  return l10n.levelRange(low.code, high.code);
}
