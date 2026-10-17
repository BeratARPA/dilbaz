import 'dart:ui' show Locale;

import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/notifications/notification_gateway.dart';
import 'package:dilbaz_app/data/notifications/notification_providers.dart';
import 'package:dilbaz_app/data/repositories/assessment_repository.dart';
import 'package:dilbaz_app/data/repositories/card_content_repository.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_store.dart';
import 'package:dilbaz_app/data/tasks/task_content_repository.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/data/tutor/speaking_annotate_request.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/speaking/application/recording_pipeline.dart';
import 'package:dilbaz_app/features/speaking/application/speaking_controller.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'late_recordings.g.dart';

/// Recordings that could not be written down or marked when they were
/// made go to the speech and tutor routes once the device is back online
/// (docs/08-speech.md §5.2): first the transcript, then the measures and
/// the tutor's marks. A task recording whose marks come this way waits in
/// the speaking task's list, and "Geri bildirimin hazır" says so once.
class LateRecordings {
  const new({
    required this._assessments,
    required this._profiles,
    required this._cards,
    required this._content,
    required this._recordings,
    required this._store,
    required this._pipeline,
    required this._notifications,
    required this._now,
  });

  final AssessmentRepository _assessments;
  final ProfileRepository _profiles;
  final CardContentRepository _cards;
  final TaskContentRepository _content;
  final RecordingRepository _recordings;
  final RecordingStore _store;
  final RecordingPipeline _pipeline;
  final NotificationGateway _notifications;
  final DateTime Function() _now;

  /// Calls to the routes in one run: the free quotas are shared.
  static const perRun = 4;

  /// A recording this young may still be processed by its own screen.
  static const settle = Duration(minutes: 5);

  /// Processes what waits on this device; how many calls were made. It
  /// stops when a route is out of reach, to try again after the next sync.
  Future<int> run(String userId) async {
    final course = await _assessments.course(userId);
    final settings = await _profiles.studySettings(userId);
    // Without the audio consent nothing recorded goes anywhere (I-18).
    if (course == null || settings == null || !settings.audioConsent) {
      return 0;
    }
    final before = _now().subtract(settle);
    final waiting = [
      for (final row in await _recordings.recordings(course.id))
        if (row.audioPath != null &&
            row.createdAt.isBefore(before) &&
            (row.asr == null || row.annotation == null))
          row,
    ];
    if (waiting.isEmpty) return 0;
    final language = await _cards.language();
    if (language == null) return 0;
    final kit = (
      language: language,
      connectors: await _content.connectors(),
      ranks: await _content.lemmaRanks(),
    );
    final tasks = {
      for (final task in await _content.speakingTasks()) task.key: task,
    };
    final scaffolds = Scaffolds.forLevel(course.level);
    var calls = 0;
    var ready = false;
    for (final row in waiting) {
      if (calls >= perRun) break;
      // Only the device that holds the audio processes it.
      final path = await _store.find(row.audioPath!);
      if (path == null) continue;
      var words = row.timedWords;
      if (words == null) {
        final bytes = await _store.read(path);
        if (bytes == null) continue;
        calls++;
        final heard = await _pipeline.transcribe(row.id, (
          bytes: bytes,
          contentType: _contentType(row.audioPath!),
          duration: Duration(milliseconds: row.durationMs),
        ));
        if (heard case Ok(:final value)) {
          words = timedWords(value);
        } else {
          break;
        }
      }
      // Nothing heard in it: nothing to mark.
      if (await _pipeline.measure(row.id, words, kit) == null) continue;
      final task = tasks[row.taskRef];
      if (task == null) continue;
      calls++;
      final marks = await _pipeline.mark(
        row.id,
        SpeakingAnnotateRequest(
          l1: settings.l1,
          l2: course.l2,
          level: course.level,
          explainInL1: scaffolds.explainInL1,
          prompt: task.prompt,
          goal: task.goal,
          canDoCodes: task.canDo,
          words: words,
          assessment: row.isAssessment,
        ),
      );
      if (marks.annotated case final annotated?) {
        await _pipeline.measure(
          row.id,
          words,
          kit,
          annotation: annotated.annotation,
        );
        if (!row.isAssessment) ready = true;
        continue;
      }
      switch (marks.waiting) {
        // The tutor cannot say, and asking again would not change that.
        case final failure?
            when failure == TutorFailure.refused ||
                failure == TutorFailure.invalid:
          await _recordings.cannotMark(row.id, failure.name);
        case _:
          // Out of reach or out of quota: later.
          return calls;
      }
    }
    if (ready) await _tell(userId);
    return calls;
  }

  /// "Geri bildirimin hazır", once, where the learner takes notifications
  /// and not in quiet hours (docs/09 §6).
  Future<void> _tell(String userId) async {
    final invitation = await _profiles.watchInvitation(userId).first;
    if (invitation == null || !invitation.wanted) return;
    final now = _now().toLocal();
    if (invitation.quiet?.covers((hour: now.hour, minute: now.minute)) ??
        false) {
      return;
    }
    if (!await _notifications.allowed()) return;
    final l10n = lookupAppLocalizations(const Locale('tr'));
    await _notifications.show(feedbackChannel(l10n), l10n.notifyFeedbackReady);
  }

  static String _contentType(String audioPath) =>
      switch (audioPath.split('.').last) {
        'webm' => 'audio/webm',
        'wav' => 'audio/wav',
        _ => 'audio/mp4',
      };
}

/// The channel the "feedback is ready" notes go out on.
NotificationChannel feedbackChannel(AppLocalizations l10n) => (
  id: 'feedback_ready',
  name: l10n.notifyFeedbackChannel,
  description: l10n.notifyFeedbackChannelDescription,
);

@Riverpod(keepAlive: true)
LateRecordings lateRecordings(Ref ref) => LateRecordings(
  assessments: ref.watch(assessmentRepositoryProvider),
  profiles: ref.watch(profileRepositoryProvider),
  cards: ref.watch(cardContentRepositoryProvider),
  content: ref.watch(taskContentRepositoryProvider),
  recordings: ref.watch(recordingRepositoryProvider),
  store: ref.watch(recordingStoreProvider),
  pipeline: ref.watch(recordingPipelineProvider),
  notifications: ref.watch(notificationGatewayProvider),
  now: ref.watch(clockProvider),
);
