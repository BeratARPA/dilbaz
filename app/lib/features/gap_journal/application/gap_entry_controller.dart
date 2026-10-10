import 'dart:async';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/data/gap/gap_providers.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/gap_journal/application/gap_suggester.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'gap_entry_controller.freezed.dart';
part 'gap_entry_controller.g.dart';

/// A capture and what becomes of it.
@freezed
abstract class GapEntryState with _$GapEntryState {
  const factory({
    required GapEntry entry,

    /// `gap_suggest` is being asked.
    @Default(false) bool asking,

    /// Why the suggestion did not come; the capture waits for a later try.
    TutorFailure? failure,

    /// The card asks the natural version; else the simple one.
    @Default(false) bool natural,

    /// The key chunk becomes a card of its own too.
    @Default(true) bool withChunk,
    @Default(false) bool saving,
  }) = _GapEntryState;
}

/// The suggestion page of one capture (A19, docs/09 §5.5). The suggestion
/// is shown at once: the learner asked for it (an exception of I-01).
@riverpod
class GapEntryController extends _$GapEntryController {
  @override
  Future<GapEntryState> build(String id) async {
    final learner = await ref.watch(gapLearnerProvider.future);
    final entry = await ref.watch(gapRepositoryProvider).entry(id);
    if (entry == null || learner == null) throw StateError('no_gap_entry');
    final waiting = entry.status == GapStatus.fresh && entry.suggestion == null;
    if (waiting) unawaited(Future(retry));
    return GapEntryState(
      entry: entry,
      asking: waiting,
      // At A levels the card asks what the learner can say now.
      natural: !learner.course.level.isAtMost(CefrLevel.a2),
    );
  }

  /// Asks for the suggestion again.
  Future<void> retry() async {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null || current.entry.suggestion != null) return;
    state = AsyncData(current.copyWith(asking: true, failure: null));
    final learner = await ref.read(gapLearnerProvider.future);
    if (learner == null || !ref.mounted) return;
    final result = await ref
        .read(gapSuggesterProvider)
        .suggest(current.entry, learner);
    if (!ref.mounted) return;
    final now = state.value ?? current;
    state = AsyncData(switch (result) {
      Ok(:final value) => now.copyWith(
        asking: false,
        entry: now.entry.copyWith(suggestion: value),
      ),
      Err(:final error) => now.copyWith(asking: false, failure: error),
    });
  }

  void choose({required bool natural}) {
    final current = state.value;
    if (current != null) state = AsyncData(current.copyWith(natural: natural));
  }

  void keepChunk({required bool keep}) {
    final current = state.value;
    if (current != null) state = AsyncData(current.copyWith(withChunk: keep));
  }

  /// Makes the chosen sentence, and the chunk if wanted, personal items.
  Future<void> addToCards() async {
    final current = state.value;
    final suggestion = current?.entry.suggestion;
    if (current == null || suggestion == null || current.saving) return;
    final learner = await ref.read(gapLearnerProvider.future);
    if (learner == null || !ref.mounted) return;
    state = AsyncData(current.copyWith(saving: true));
    final sentence = current.natural
        ? suggestion.l2Natural
        : suggestion.l2Simple;
    final other = current.natural ? suggestion.l2Simple : suggestion.l2Natural;
    final gaps = ref.read(gapRepositoryProvider);
    final language = await ref.read(cardContentRepositoryProvider).language();
    // The lemmas of the pack's forms; an unknown word is its own lemma.
    List<String> lemmasOf(String text) => language == null
        ? const []
        : {
            for (final word in language.tokenize(text))
              ...language.lemmasOf(word),
          }.toList();
    final chunk = current.withChunk && _ownChunk(suggestion, sentence)
        ? suggestion.keyChunk
        : null;
    await gaps.addToCards(
      userId: learner.userId,
      courseId: learner.course.id,
      id: current.entry.id,
      sentence: sentence,
      variants: [other],
      sentenceLemmas: lemmasOf(sentence),
      chunk: chunk,
      chunkLemmas: chunk == null ? const [] : lemmasOf(chunk.text),
      notes: suggestion.notesL1,
    );
    await _reload(current);
  }

  Future<void> dismiss() async {
    final current = state.value;
    if (current == null || current.saving) return;
    state = AsyncData(current.copyWith(saving: true));
    await ref.read(gapRepositoryProvider).dismiss(current.entry.id);
    await _reload(current);
  }

  /// Whether the chunk is more than the sentence itself.
  static bool _ownChunk(GapSuggestion suggestion, String sentence) {
    String plain(String text) => text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\s]', unicode: true), '')
        .trim();
    return plain(suggestion.keyChunk.text) != plain(sentence);
  }

  Future<void> _reload(GapEntryState current) async {
    final entry = await ref.read(gapRepositoryProvider).entry(current.entry.id);
    if (!ref.mounted) return;
    state = AsyncData(
      current.copyWith(entry: entry ?? current.entry, saving: false),
    );
  }
}

/// The course's captures, newest first; the ones still waiting for their
/// suggestion are asked again once when the list opens.
@riverpod
Stream<List<GapEntry>> gapEntries(Ref ref) async* {
  final learner = await ref.watch(gapLearnerProvider.future);
  if (learner == null) {
    yield const [];
    return;
  }
  var caughtUp = false;
  await for (final entries
      in ref.watch(gapRepositoryProvider).watchEntries(learner.course.id)) {
    if (!caughtUp) {
      caughtUp = true;
      unawaited(ref.read(gapSuggesterProvider).catchUp(entries, learner));
    }
    yield entries;
  }
}
