import 'dart:async';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/data/gap/gap_providers.dart';
import 'package:dilbaz_app/data/speech/dictation.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/features/gap_journal/application/gap_suggester.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'gap_capture_controller.freezed.dart';
part 'gap_capture_controller.g.dart';

/// The capture page (A19, docs/09 §5.5).
@freezed
abstract class GapCaptureState with _$GapCaptureState {
  const factory({
    /// There is a course to capture for.
    required bool ready,

    /// Speaking is allowed (audio consent, docs/14 §4).
    required bool canDictate,
    @Default(false) bool listening,
    @Default(false) bool saving,
    DictationFailure? failure,

    /// The latest words dictated; [heardCount] tells a new one apart.
    String? heard,
    @Default(0) int heardCount,
  }) = _GapCaptureState;
}

/// Writes down a capture, by keyboard or in the learner's own language by
/// voice, and stores it; its suggestion is asked for on its own page.
@riverpod
class GapCaptureController extends _$GapCaptureController {
  Timer? _limit;

  @override
  Future<GapCaptureState> build() async {
    ref.onDispose(() => _limit?.cancel());
    // Kept for the whole page.
    ref.watch(dictationProvider);
    final learner = await ref.watch(gapLearnerProvider.future);
    return GapCaptureState(
      ready: learner != null,
      canDictate: learner?.settings.audioConsent ?? false,
    );
  }

  Future<void> startDictation() async {
    final current = state.value;
    if (current == null || !current.canDictate || current.listening) return;
    state = AsyncData(current.copyWith(listening: true, failure: null));
    final started = await ref.read(dictationProvider).start();
    if (!ref.mounted) return;
    if (started case Err(:final error)) {
      state = AsyncData(current.copyWith(listening: false, failure: error));
      return;
    }
    _limit = Timer(
      DeviceFirstDictation.limit,
      () => unawaited(stopDictation()),
    );
  }

  Future<void> stopDictation() async {
    final current = state.value;
    if (current == null || !current.listening) return;
    _limit?.cancel();
    final heard = await ref.read(dictationProvider).stop();
    if (!ref.mounted) return;
    final now = state.value ?? current;
    state = AsyncData(switch (heard) {
      Ok(value: final text) => now.copyWith(
        listening: false,
        heard: text,
        heardCount: now.heardCount + 1,
      ),
      Err(:final error) => now.copyWith(listening: false, failure: error),
    });
  }

  /// Stores the capture; its id, or null when there is nothing to store.
  Future<String?> save({
    required String text,
    required GapContext context,
    String? note,
  }) async {
    final current = state.value;
    if (current == null || current.saving || text.trim().isEmpty) return null;
    final learner = await ref.read(gapLearnerProvider.future);
    if (learner == null) return null;
    state = AsyncData(current.copyWith(saving: true));
    if (current.listening) await ref.read(dictationProvider).cancel();
    final entry = await ref
        .read(gapRepositoryProvider)
        .capture(
          userId: learner.userId,
          courseId: learner.course.id,
          l1Text: text,
          context: context,
          note: note,
        );
    if (ref.mounted) {
      state = AsyncData(current.copyWith(saving: false, listening: false));
    }
    return entry.id;
  }
}
