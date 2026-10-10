import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/fsrs/card_mode.dart';
import 'package:dilbaz_engine/src/planner/strand.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'planner_config.freezed.dart';

/// Settings of the session planner (docs/05-session-planner.md §7). The
/// defaults are the documented values; experiments may override them.
@freezed
abstract class PlannerConfig with _$PlannerConfig {
  /// Creates planner settings.
  const factory({
    /// Longest review block on an ordinary day.
    @Default(Duration(minutes: 10)) Duration reviewCap,

    /// Largest share of the day's budget that reviews may take.
    @Default(0.4) double reviewShare,

    /// At or under this budget the day is a minimum day: reviews only.
    @Default(Duration(minutes: 7)) Duration minimumDayBudget,

    /// Options are offered only with at least this much time left.
    @Default(Duration(minutes: 5)) Duration optionsMinimum,

    /// Most new items a day, by level (I-07).
    @Default(<CefrLevel, int>{
      CefrLevel.a0: 6,
      CefrLevel.a1: 8,
      CefrLevel.a2: 10,
      CefrLevel.b1: 10,
      CefrLevel.b2: 12,
      CefrLevel.c1: 12,
      CefrLevel.c2: 12,
    })
    Map<CefrLevel, int> maxNew,

    /// Share of the review cap that projected reviews may fill before new
    /// items stop (I-07).
    @Default(0.8) double newLoadShare,

    /// What one new card adds to daily reviews in its first week.
    @Default(Duration(seconds: 72)) Duration newCardDailyCost,

    /// Under this share of first-try recalls new items are halved (P10).
    @Default(0.70) double lowAccuracyThreshold,

    /// Weight of each mode in review priority; spoken production leads.
    @Default(<CardMode, double>{
      CardMode.speak: 1,
      CardMode.contrast: 1,
      CardMode.type: 0.9,
      CardMode.cloze: 0.9,
      CardMode.dictation: 0.8,
      CardMode.recognizeAudio: 0.6,
    })
    Map<CardMode, double> modeWeight,

    /// Added to the priority of cards tied to the weekly error focus.
    @Default(0.15) double focusBonus,

    /// Time one review takes, by mode, until the learner's own medians are
    /// known (docs/05 §5).
    @Default(<CardMode, Duration>{
      CardMode.speak: Duration(seconds: 20),
      CardMode.type: Duration(seconds: 25),
      CardMode.cloze: Duration(seconds: 20),
      CardMode.contrast: Duration(seconds: 20),
      CardMode.recognizeAudio: Duration(seconds: 8),
      CardMode.dictation: Duration(seconds: 45),
    })
    Map<CardMode, Duration> cardDuration,

    /// Time the introduction of a new item takes, before its first card.
    @Default(Duration(seconds: 30)) Duration introductionDuration,

    /// Days a week the learner aims to study.
    @Default(5) int weeklyDaysGoal,

    /// Share of the week's time each strand should get, by level.
    @Default(<CefrLevel, Map<Strand, double>>{
      CefrLevel.a0: {
        Strand.language: 0.50,
        Strand.output: 0.15,
        Strand.input: 0.20,
        Strand.fluency: 0.15,
      },
      CefrLevel.a1: {
        Strand.language: 0.40,
        Strand.output: 0.20,
        Strand.input: 0.25,
        Strand.fluency: 0.15,
      },
      CefrLevel.a2: {
        Strand.language: 0.35,
        Strand.output: 0.25,
        Strand.input: 0.25,
        Strand.fluency: 0.15,
      },
      CefrLevel.b1: {
        Strand.language: 0.25,
        Strand.output: 0.25,
        Strand.input: 0.30,
        Strand.fluency: 0.20,
      },
      CefrLevel.b2: {
        Strand.language: 0.20,
        Strand.output: 0.30,
        Strand.input: 0.35,
        Strand.fluency: 0.15,
      },
      CefrLevel.c1: {
        Strand.language: 0.15,
        Strand.output: 0.30,
        Strand.input: 0.40,
        Strand.fluency: 0.15,
      },
      CefrLevel.c2: {
        Strand.language: 0.15,
        Strand.output: 0.30,
        Strand.input: 0.40,
        Strand.fluency: 0.15,
      },
    })
    Map<CefrLevel, Map<Strand, double>> strandTargets,
  }) = _PlannerConfig;
}
