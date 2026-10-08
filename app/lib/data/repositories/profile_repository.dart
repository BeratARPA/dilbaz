import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';

/// Why the profile could not be read from or written to the server.
enum ProfileFailure { network, unknown }

/// What a study session needs of the profile (docs/13 §2.1).
typedef StudySettings = ({
  /// The learner's own language.
  String l1,

  /// Answers are typed by default; always so without audio consent.
  bool silentMode,

  /// Time the learner wants to spend a day (I-13).
  Duration dailyBudget,

  /// Days a week the learner wants to study.
  int weeklyDaysGoal,

  /// When the learner studies: the code of their first habit anchor
  /// (`morning_coffee`, …); null without one.
  String? anchor,

  /// Recording audio is allowed (docs/14 §4).
  bool audioConsent,
});

/// The daily invitation as the learner set it (docs/09 §6).
typedef InvitationSettings = ({
  /// The learner asked for it, and the system allowed notifications
  /// then (`daily_invitation`).
  bool wanted,

  /// The code of the habit anchor it goes with (`morning_coffee`, …).
  String? anchor,

  /// The anchor's time.
  DayTime? time,

  /// When nothing goes out (`quiet_hours`).
  QuietHours? quiet,
});

/// The learner's profile and course (docs/13-data-model.md §2.1).
///
/// Local first: the welcome flow writes to the local database and the
/// outbox; [push] sends the two rows right away, because teams need the
/// profile on the server before the general sync exists.
abstract interface class ProfileRepository {
  /// Whether [userId] has finished the welcome flow, as far as this device
  /// knows.
  Stream<bool> watchOnboarded(String userId);

  /// Whether [userId] consented to recording audio (docs/14 §4); false
  /// before the welcome flow.
  Stream<bool> watchAudioConsent(String userId);

  /// The daily invitation of [userId], and again whenever the profile
  /// changes; null before the welcome flow.
  Stream<InvitationSettings?> watchInvitation(String userId);

  /// The study settings of [userId]; null before the welcome flow.
  Future<StudySettings?> studySettings(String userId);

  /// Brings a profile made on another device here. True if there was one.
  Future<Result<bool, ProfileFailure>> restore(String userId);

  /// Saves the answers of the welcome flow: the profile and its course.
  /// The flow saves before its team step too, which needs the profile on
  /// the server; only a [finished] save ends the flow.
  Future<void> create(
    String userId,
    OnboardingAnswers answers, {
    required bool finished,
  });

  /// Sends the profile and the course to the server.
  Future<Result<void, ProfileFailure>> push(String userId);
}
