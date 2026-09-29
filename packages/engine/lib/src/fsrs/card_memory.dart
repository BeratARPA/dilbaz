import 'package:dilbaz_engine/src/fsrs/memory_state.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'card_memory.freezed.dart';
part 'card_memory.g.dart';

/// FSRS memory of one card (learner × item × mode).
///
/// This is the engine's own type; `package:fsrs` types never leave the
/// `fsrs` module. The JSON form is stored as `attempts.card_state_after`
/// so that sync stays deterministic (docs/12-architecture.md §5), and it
/// holds every FSRS column of `cards`. `package:fsrs` keeps no review
/// counts, so the scheduler counts [reps] and [lapses] itself.
/// All timestamps are UTC.
@freezed
abstract class CardMemory with _$CardMemory {
  /// Creates a card memory.
  const factory({
    /// FSRS card id, kept separately from the Dilbaz card UUID.
    required int fsrsCardId,

    /// Current learning state.
    required MemoryState state,

    /// When the card is due next (UTC).
    required DateTime due,

    /// Learning or relearning step; null in the review state.
    int? step,

    /// FSRS stability in days; null before the first review.
    double? stability,

    /// FSRS difficulty (1–10); null before the first review.
    double? difficulty,

    /// Time of the last review (UTC); null before the first review.
    DateTime? lastReview,

    /// Reviews so far.
    @Default(0) int reps,

    /// Times the card was forgotten after graduating (Again in review).
    @Default(0) int lapses,
  }) = _CardMemory;

  /// Reads a card memory from its `card_state_after` JSON form.
  factory fromJson(Map<String, Object?> json) => _$CardMemoryFromJson(json);
}
