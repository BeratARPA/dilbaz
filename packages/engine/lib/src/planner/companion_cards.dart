import 'package:dilbaz_engine/src/curriculum/cefr_level.dart';
import 'package:dilbaz_engine/src/curriculum/item_kind.dart';
import 'package:dilbaz_engine/src/model/item_level.dart';

/// The cards an item gets besides its production card (docs/03 A03, A04;
/// user decision 2026-10-17). Each is a card of its own, scheduled by FSRS
/// (I-08); the planner's review ceiling counts it (I-07).
abstract final class CompanionCards {
  /// Listen and understand (A03): a word or a chunk gets it when it is
  /// introduced while the learner is at A0–B1, the levels where hearing a
  /// known word is the gap. Receptive only (I-05).
  static bool listening({required ItemKind kind, required CefrLevel level}) =>
      (kind == ItemKind.wordSense || kind == ItemKind.chunk) &&
      level.index <= CefrLevel.b1.index;

  /// Gap in context (A04): a word gets it from A1, once it is produced at
  /// the recallable level; the form is called up in its sentence, spaced
  /// apart from the production card.
  static bool cloze({
    required ItemKind kind,
    required CefrLevel level,
    required ItemLevel production,
  }) =>
      kind == ItemKind.wordSense &&
      level.index >= CefrLevel.a1.index &&
      production.isAtLeast(ItemLevel.recallable);
}
