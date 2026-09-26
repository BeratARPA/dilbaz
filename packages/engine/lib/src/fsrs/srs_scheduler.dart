import 'package:dilbaz_engine/src/fsrs/card_memory.dart';
import 'package:dilbaz_engine/src/fsrs/memory_state.dart';
import 'package:dilbaz_engine/src/fsrs/review_rating.dart';
import 'package:dilbaz_engine/src/fsrs/srs_config.dart';
// The prefix is mandatory: fsrs `Card` and `State` clash with Flutter names.
import 'package:fsrs/fsrs.dart' as fsrs;

/// The engine's only gateway to FSRS (I-08: intervals come from FSRS only).
///
/// Every timestamp given to or returned by the scheduler is UTC; a non-UTC
/// value is a programming error and throws [ArgumentError].
final class SrsScheduler {
  /// Creates a scheduler for one mode group.
  new([this.config = const SrsConfig()])
    : _scheduler = fsrs.Scheduler(
        parameters: config.parameters ?? fsrs.defaultParameters,
        desiredRetention: _checkedRetention(config.desiredRetention),
        enableFuzzing: config.enableFuzzing,
      );

  /// Largest FSRS card id; ids must stay exact as web (JS) integers.
  static const maxFsrsCardId = 9007199254740991;

  /// Settings this scheduler was built with.
  final SrsConfig config;

  final fsrs.Scheduler _scheduler;

  /// Memory of a card that has never been reviewed; due at [now].
  CardMemory newCard({required int fsrsCardId, required DateTime now}) {
    if (fsrsCardId <= 0 || fsrsCardId > maxFsrsCardId) {
      throw ArgumentError.value(fsrsCardId, 'fsrsCardId', 'out_of_range');
    }
    _requireUtc(now, 'now');
    return _fromFsrs(fsrs.Card(cardId: fsrsCardId, due: now));
  }

  /// Applies one review with an engine-computed [rating] at time [at].
  CardMemory review(
    CardMemory card,
    ReviewRating rating, {
    required DateTime at,
  }) {
    _requireUtc(at, 'at');
    final result = _scheduler.reviewCard(
      _toFsrs(card),
      fsrs.Rating.fromValue(rating.code),
      reviewDateTime: at,
    );
    return _fromFsrs(result.card);
  }

  /// Predicted probability of recalling [card] at [at]; 0 before any review.
  double retrievability(CardMemory card, {required DateTime at}) {
    _requireUtc(at, 'at');
    return _scheduler.getCardRetrievability(_toFsrs(card), currentDateTime: at);
  }

  static double _checkedRetention(double value) {
    if (value < SrsConfig.minDesiredRetention ||
        value > SrsConfig.maxDesiredRetention) {
      throw ArgumentError.value(value, 'desiredRetention', 'out_of_range');
    }
    return value;
  }

  static void _requireUtc(DateTime value, String name) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, name, 'utc_required');
    }
  }

  static fsrs.Card _toFsrs(CardMemory card) {
    _requireUtc(card.due, 'due');
    final lastReview = card.lastReview;
    if (lastReview != null) _requireUtc(lastReview, 'lastReview');
    return fsrs.Card(
      cardId: card.fsrsCardId,
      state: fsrs.State.fromValue(card.state.code),
      step: card.step,
      stability: card.stability,
      difficulty: card.difficulty,
      due: card.due,
      lastReview: lastReview,
    );
  }

  static CardMemory _fromFsrs(fsrs.Card card) => CardMemory(
    fsrsCardId: card.cardId,
    state: MemoryState.values.firstWhere((s) => s.code == card.state.value),
    due: card.due,
    step: card.step,
    stability: card.stability,
    difficulty: card.difficulty,
    lastReview: card.lastReview,
  );
}
