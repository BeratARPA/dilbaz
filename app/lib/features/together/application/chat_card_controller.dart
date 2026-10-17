import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/session_providers.dart';
import 'package:dilbaz_app/data/tasks/task_content_repository.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/features/together/application/together_controller.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_card_controller.freezed.dart';
part 'chat_card_controller.g.dart';

/// A chat card on screen (A14): before, while and after the partners talk.
@freezed
sealed class ChatCardState with _$ChatCardState {
  /// The card is not in the packs on this device.
  const factory unavailable() = ChatCardUnavailable;

  /// The card, and whether its meanings are shown (the level's scaffold,
  /// docs/02 §3). [startedAt] is set once the two began talking.
  const factory open({
    required ChatCard card,
    required bool meanings,
    DateTime? startedAt,
  }) = ChatCardOpen;

  /// They talked for [spent].
  const factory done({required ChatCard card, required Duration spent}) =
      ChatCardDone;
}

/// A chat card session (A14): face to face, nothing recorded; its time goes
/// to the output strand and to the partners' weekly goal (F2-09).
@riverpod
class ChatCardController extends _$ChatCardController {
  late ({String userId, String courseId, String deviceId}) _context;

  /// Longest time a chat counts: a card left open is not study time.
  static const cap = Duration(minutes: 30);

  @override
  Future<ChatCardState> build(String key) async {
    final userId = ref.watch(authRepositoryProvider).userId;
    if (userId == null) return const ChatCardState.unavailable();
    final course = await ref.watch(assessmentRepositoryProvider).course(userId);
    final card = (await ref.watch(taskContentRepositoryProvider).chatCards())
        .where((c) => c.key == key)
        .firstOrNull;
    if (course == null || card == null) {
      return const ChatCardState.unavailable();
    }
    _context = (
      userId: userId,
      courseId: course.id,
      deviceId: await ref.watch(deviceRepositoryProvider).deviceId(userId),
    );
    return ChatCardState.open(
      card: card,
      meanings: Scaffolds.forLevel(course.level).explainInL1,
    );
  }

  /// The two began talking.
  void start() {
    if (state.value case final ChatCardOpen open when open.startedAt == null) {
      state = AsyncData(open.copyWith(startedAt: ref.read(clockProvider)()));
    }
  }

  /// They are done: the time goes to the session, up to the cap.
  Future<void> finish() async {
    final open = state.value;
    if (open is! ChatCardOpen) return;
    final startedAt = open.startedAt;
    if (startedAt == null) return;
    final now = ref.read(clockProvider)();
    final talked = now.difference(startedAt);
    final spent = talked > cap ? cap : talked;
    await ref
        .read(sessionRepositoryProvider)
        .record(
          userId: _context.userId,
          courseId: _context.courseId,
          deviceId: _context.deviceId,
          startedAt: startedAt,
          endedAt: now,
          strands: {Strand.output: spent},
          planned: {'activity': chatActivity, 'task': open.card.key},
          done: {'with_partner': true},
        );
    if (!ref.mounted) return;
    state = AsyncData(ChatCardState.done(card: open.card, spent: spent));
  }
}
