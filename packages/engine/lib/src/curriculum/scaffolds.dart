import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/scoring/card_review.dart';

/// The guidance a level gets on cards and speaking tasks
/// (docs/02-curriculum.md §3, I-09): scaffolds close as the level rises.
/// Read from the level code, never from a pack.
final class Scaffolds {
  /// Scaffolds as given.
  const new({
    required this.explainInL1,
    required this.slowAudio,
    required this.autoHintLevel,
    required this.maxAttempts,
    required this.taskPreparation,
    required this.taskPhrases,
  });

  /// The scaffolds of [level].
  factory forLevel(CefrLevel level) => switch (level) {
    // H1–H4; the answer opens by itself after two misses.
    CefrLevel.a0 => const Scaffolds(
      explainInL1: true,
      slowAudio: true,
      autoHintLevel: CardReview.answerLevel,
      maxAttempts: 2,
      taskPreparation: Duration(seconds: 90),
      taskPhrases: true,
    ),
    CefrLevel.a1 => const Scaffolds(
      explainInL1: true,
      slowAudio: true,
      autoHintLevel: CardReview.answerLevel,
      maxAttempts: CardReview.defaultMaxAttempts,
      taskPreparation: Duration(seconds: 60),
      taskPhrases: true,
    ),
    CefrLevel.a2 => const Scaffolds(
      explainInL1: true,
      slowAudio: false,
      autoHintLevel: CardReview.answerLevel,
      maxAttempts: CardReview.defaultMaxAttempts,
      taskPreparation: Duration(seconds: 60),
      taskPhrases: true,
    ),
    // H1–H3; the answer on request.
    CefrLevel.b1 => const Scaffolds(
      explainInL1: false,
      slowAudio: false,
      autoHintLevel: 3,
      maxAttempts: CardReview.defaultMaxAttempts,
      taskPreparation: Duration(seconds: 30),
      taskPhrases: false,
    ),
    // H1–H2; the rest on request.
    CefrLevel.b2 => const Scaffolds(
      explainInL1: false,
      slowAudio: false,
      autoHintLevel: 2,
      maxAttempts: CardReview.defaultMaxAttempts,
      taskPreparation: Duration(seconds: 15),
      taskPhrases: false,
    ),
    // H1; the rest on request.
    CefrLevel.c1 || CefrLevel.c2 => const Scaffolds(
      explainInL1: false,
      slowAudio: false,
      autoHintLevel: 1,
      maxAttempts: CardReview.defaultMaxAttempts,
      taskPreparation: Duration(seconds: 15),
      taskPhrases: false,
    ),
  };

  /// Explanations and hints in the learner's language (else the target's).
  final bool explainInL1;

  /// The slowed clip (0.8×) plays by default.
  final bool slowAudio;

  /// Highest hint a miss opens by itself; higher ones open on request.
  final int autoHintLevel;

  /// Misses before the review ends and the answer is shown.
  final int maxAttempts;

  /// Time to prepare before a speaking task (A11); it can be cut short.
  final Duration taskPreparation;

  /// A speaking task shows its phrases by default; above A2 they open on
  /// request.
  final bool taskPhrases;

  /// A review of a card with these scaffolds.
  CardReview review() =>
      CardReview(maxAttempts: maxAttempts, autoHintLevel: autoHintLevel);
}
