import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/card_feedback_repository.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/device_repository.dart';
import 'package:dilbaz_app/data/tutor/answer_check_request.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:dilbaz_app/data/tutor/tutor_providers.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'late_checks.g.dart';

/// Answers the tutor could not check in time, or that the learner
/// disputed, go to it once the device is back online (docs/03 §0.5 steps
/// 4–5, docs/07-ai-tutor.md §7). Its verdict comes as `llm_resolved`: it
/// corrects the evidence and teaches the learner's own answers; the
/// review's rating and the schedule stay as they were (I-03, I-08).
class LateChecks {
  const new({
    required this._feedback,
    required this._tutor,
    required this._devices,
  });

  final CardFeedbackRepository _feedback;
  final TutorRepository _tutor;
  final DeviceRepository _devices;

  /// Answers checked in one run: the free quota is shared (docs/07 §3).
  static const perRun = 10;

  /// Checks the answers given on this device that wait; how many were
  /// settled. It stops when the tutor is out of reach, to try again after
  /// the next sync.
  Future<int> run(String userId) async {
    final deviceId = await _devices.deviceId(userId);
    final waiting = await _feedback.waiting(deviceId, limit: perRun);
    var settled = 0;
    for (final (:attemptId, :request, :targetIntact) in waiting) {
      final checked = await _tutor.answerCheck(
        AnswerCheckRequest.fromJson(request),
      );
      final verdict = switch (checked) {
        Ok(:final value) => lateVerdict(value, targetIntact: targetIntact),
        // The tutor cannot say, and asking again would not change that.
        Err(:final error)
            when error == TutorFailure.refused ||
                error == TutorFailure.invalid =>
          {'code': error.name},
        Err() => null,
      };
      if (verdict == null) break;
      await _feedback.resolve(
        userId: userId,
        attemptId: attemptId,
        verdict: verdict,
      );
      settled++;
    }
    return settled;
  }
}

/// The `llm_resolved` payload of a check (docs/13-data-model.md §2.3). A
/// minor error's target is [targetIntact], the engine's word kept with the
/// answer, when there is one (ADR-0010).
Map<String, Object?> lateVerdict(LlmAnswerCheck check, {bool? targetIntact}) {
  final evaluation = targetIntact == null
      ? check.evaluation
      : check.evaluation.settled(targetIntact: targetIntact);
  return {
    'verdict': evaluation.verdict.code,
    'target_ok': evaluation.targetOk,
    'error_tags': check.errorTags,
    'provider': check.provider,
    'model': check.model,
    'catalog': check.catalog,
    'confidence': check.confidence,
  };
}

@Riverpod(keepAlive: true)
LateChecks lateChecks(Ref ref) => LateChecks(
  feedback: ref.watch(cardFeedbackRepositoryProvider),
  tutor: ref.watch(tutorRepositoryProvider),
  devices: ref.watch(deviceRepositoryProvider),
);
