import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'placement_state.freezed.dart';

/// Parts of the placement test, in order (docs/06-assessment.md §2).
enum PlacementPart { words, grammar, dictation }

/// What a placement test found, for the learner to read.
@freezed
abstract class PlacementReport with _$PlacementReport {
  const factory({
    /// The level the curriculum starts at.
    required CefrLevel start,

    /// Words recognized among the most frequent ones; null when the
    /// vocabulary part was not finished.
    int? vocabulary,

    /// The learner said yes to so many made-up words that [vocabulary] is
    /// guesswork.
    @Default(false) bool guesswork,
    LevelEstimate? vocabularyLevel,
    LevelEstimate? grammarLevel,
    LevelEstimate? listeningLevel,

    /// The course had a test before; the parts finished now replaced its
    /// results.
    @Default(false) bool retake,

    /// The course has no speaking recording yet, so the baseline is
    /// offered (docs/06 §2 part 4).
    @Default(false) bool offerBaseline,
  }) = _PlacementReport;
}

/// Where the learner is in the placement test.
@freezed
sealed class PlacementState with _$PlacementState {
  /// The device has no placement test for the course yet.
  const factory unavailable() = PlacementUnavailable;

  /// Before the test: what it is, and the [parts] it has. [retake]: the
  /// course had a test before.
  const factory overview({
    required List<PlacementPart> parts,
    @Default(false) bool retake,
  }) = PlacementOverview;

  /// Before a part: what it asks for.
  const factory partIntro({required PlacementPart part}) = PlacementPartIntro;

  /// Vocabulary: does the learner know [word]?
  const factory word({
    required int number,
    required int total,
    required String word,
  }) = PlacementWord;

  /// Grammar: which of [options] fills the gap in [stem]?
  const factory question({
    required int number,
    required String stem,
    required List<String> options,
  }) = PlacementQuestion;

  /// Dictation: the learner listens to a sentence and writes it down.
  const factory listening({
    required int number,
    required int total,

    /// Times the sentence may still be played.
    required int playsLeft,
    @Default(false) bool playing,

    /// The clip was played at least once.
    @Default(false) bool heard,

    /// Why the clip could not be played.
    PackFailure? failure,
  }) = PlacementListening;

  const factory saving() = PlacementSaving;

  /// The test is over: [report] tells what it found; null when the
  /// learner left before finishing a part.
  const factory done({PlacementReport? report}) = PlacementDone;
}
