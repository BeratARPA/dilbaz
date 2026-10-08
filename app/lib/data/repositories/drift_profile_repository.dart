import 'package:dilbaz_app/core/config/course_defaults.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:dilbaz_app/data/repositories/onboarding_answers.dart';
import 'package:dilbaz_app/data/repositories/profile_remote.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/repositories/profile_rows.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

String _uuidV7() => const Uuid().v7();

class DriftProfileRepository implements ProfileRepository {
  new(this._db, this._remote, {this._now = nowUtc, this._newId = _uuidV7});

  final AppDatabase _db;
  final ProfileRemote _remote;
  final DateTime Function() _now;
  final String Function() _newId;

  static const _profiles = 'profiles';
  static const _courses = 'courses';
  static const _upsert = 'upsert';

  /// Key in `profiles.settings`: when the welcome flow was finished.
  static const onboardedAt = 'onboarded_at';

  @override
  Stream<bool> watchOnboarded(String userId) =>
      (_db.select(_db.profiles)..where((t) => t.id.equals(userId)))
          .watchSingleOrNull()
          .map((row) => row?.settings[onboardedAt] != null);

  @override
  Stream<bool> watchAudioConsent(String userId) =>
      (_db.select(_db.profiles)..where((t) => t.id.equals(userId)))
          .watchSingleOrNull()
          .map((row) => _consented(row?.settings));

  static const _audioConsent = 'audio_consent';
  static const _silentMode = 'silent_mode';

  static bool _consented(Map<String, Object?>? settings) =>
      switch (settings?[_audioConsent]) {
        {'granted': true} => true,
        _ => false,
      };

  @override
  Future<StudySettings?> studySettings(String userId) async {
    final row = await (_db.select(
      _db.profiles,
    )..where((t) => t.id.equals(userId))).getSingleOrNull();
    if (row == null) return null;
    final consent = _consented(row.settings);
    return (
      l1: row.l1,
      // Without consent nothing is recorded, whatever the setting says.
      silentMode: row.settings[_silentMode] == true || !consent,
      dailyBudget: Duration(minutes: row.timeBudgetMin),
      weeklyDaysGoal: row.weeklyDaysGoal,
      anchor: switch (row.anchors) {
        [{'label': final String label}, ...] => label,
        _ => null,
      },
      audioConsent: consent,
    );
  }

  @override
  Future<Result<bool, ProfileFailure>> restore(String userId) async {
    switch (await _remote.fetch(userId)) {
      case Err(:final error):
        return Err(error);
      case Ok(value: null):
        return const Ok(false);
      case Ok(value: (:final profile, :final courses)):
        await _db.transaction(() async {
          await _db
              .into(_db.profiles)
              .insertOnConflictUpdate(profileFromServer(profile));
          for (final course in courses) {
            await _db
                .into(_db.courses)
                .insertOnConflictUpdate(courseFromServer(course));
          }
        });
        return const Ok(true);
    }
  }

  @override
  Future<void> create(
    String userId,
    OnboardingAnswers answers, {
    required bool finished,
  }) async {
    final now = _now();
    final at = now.toIso8601String();
    final level = CefrLevel.values.firstWhere((l) => l.code == answers.level);
    final goalText = answers.goalText.trim();
    await _db.transaction(() async {
      final profile = await (_db.select(
        _db.profiles,
      )..where((t) => t.id.equals(userId))).getSingleOrNull();
      final course =
          await (_db.select(_db.courses)..where(
                (t) => t.profileId.equals(userId) & t.l2.equals(defaultL2),
              ))
              .getSingleOrNull();
      final courseId = course?.id ?? _newId();
      await _db
          .into(_db.profiles)
          .insertOnConflictUpdate(
            ProfilesCompanion.insert(
              id: userId,
              displayName: answers.displayName.trim(),
              l1: const Value(defaultL1),
              timeBudgetMin: Value(answers.timeBudgetMin),
              weeklyDaysGoal: Value(answers.weeklyDaysGoal),
              anchors: Value([
                {'label': answers.anchor, 'time': answers.anchorTime},
              ]),
              goalText: Value(goalText.isEmpty ? null : goalText),
              interests: Value(answers.goals.toList()..sort()),
              settings: Value({
                _audioConsent: {'granted': answers.audioConsent, 'at': at},
                'ai_data_consent': {'granted': answers.aiDataConsent, 'at': at},
                'daily_invitation': answers.notifications,
                // Without consent or a microphone, answers are typed.
                _silentMode: !(answers.audioConsent && answers.microphone),
                if (finished) onboardedAt: at,
              }),
              updatedAt: Value(now),
              createdAt: Value(profile?.createdAt ?? now),
              pendingPush: const Value(true),
            ),
          );
      await _db
          .into(_db.courses)
          .insertOnConflictUpdate(
            CoursesCompanion.insert(
              id: courseId,
              profileId: userId,
              l2: defaultL2,
              pairPack: '$defaultL1-$defaultL2',
              // Self-reported until the placement test (docs/04 §10).
              levelEstimates: Value({
                'overall': {
                  'low': level.scale,
                  'high': level.scale,
                  'confidence': 'low',
                  'source': 'self',
                },
              }),
              updatedAt: Value(now),
              createdAt: Value(course?.createdAt ?? now),
              pendingPush: const Value(true),
            ),
          );
      await _db.batch((batch) {
        batch.insertAll(_db.outbox, [
          OutboxCompanion.insert(
            targetTable: _profiles,
            rowId: userId,
            op: _upsert,
          ),
          OutboxCompanion.insert(
            targetTable: _courses,
            rowId: courseId,
            op: _upsert,
          ),
        ]);
      });
    });
  }

  @override
  Future<Result<void, ProfileFailure>> push(String userId) async {
    final profile = await (_db.select(
      _db.profiles,
    )..where((t) => t.id.equals(userId))).getSingleOrNull();
    if (profile == null) return const Ok(null);
    final courses = await (_db.select(
      _db.courses,
    )..where((t) => t.profileId.equals(userId))).get();
    final pushed = await _remote.upsert(
      profile: profileToServer(profile),
      courses: [for (final course in courses) courseToServer(course)],
    );
    if (pushed is Err) return pushed;

    final courseIds = [for (final course in courses) course.id];
    await _db.transaction(() async {
      await (_db.update(_db.profiles)..where((t) => t.id.equals(userId))).write(
        const ProfilesCompanion(pendingPush: Value(false)),
      );
      await (_db.update(_db.courses)..where((t) => t.id.isIn(courseIds))).write(
        const CoursesCompanion(pendingPush: Value(false)),
      );
      await (_db.delete(_db.outbox)..where(
            (t) =>
                (t.targetTable.equals(_profiles) & t.rowId.equals(userId)) |
                (t.targetTable.equals(_courses) & t.rowId.isIn(courseIds)),
          ))
          .go();
    });
    return const Ok(null);
  }
}
