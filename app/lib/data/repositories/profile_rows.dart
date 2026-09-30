import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:drift/drift.dart';

// Server rows (column name → value, docs/13-data-model.md §2.1) to and from
// the local tables. `server_seq` is the server's to assign and is never sent.

DateTime _utc(Object? value) => DateTime.parse(value! as String).toUtc();

ProfilesCompanion profileFromServer(Map<String, Object?> row) =>
    ProfilesCompanion.insert(
      id: row['id']! as String,
      displayName: row['display_name']! as String,
      l1: Value(row['l1']! as String),
      uiLocale: Value(row['ui_locale']! as String),
      timeBudgetMin: Value(row['time_budget_min']! as int),
      weeklyDaysGoal: Value(row['weekly_days_goal']! as int),
      anchors: Value(row['anchors']! as List<Object?>),
      quietHours: Value(row['quiet_hours'] as Map<String, Object?>?),
      goalText: Value(row['goal_text'] as String?),
      interests: Value((row['interests']! as List<Object?>).cast<String>()),
      scaffoldOverrides: Value(
        row['scaffold_overrides']! as Map<String, Object?>,
      ),
      settings: Value(row['settings']! as Map<String, Object?>),
      updatedAt: Value(_utc(row['updated_at'])),
      serverSeq: Value(row['server_seq'] as int?),
      createdAt: Value(_utc(row['created_at'])),
    );

Map<String, Object?> profileToServer(ProfileRow row) => {
  'id': row.id,
  'display_name': row.displayName,
  'l1': row.l1,
  'ui_locale': row.uiLocale,
  'time_budget_min': row.timeBudgetMin,
  'weekly_days_goal': row.weeklyDaysGoal,
  'anchors': row.anchors,
  'quiet_hours': row.quietHours,
  'goal_text': row.goalText,
  'interests': row.interests,
  'scaffold_overrides': row.scaffoldOverrides,
  'settings': row.settings,
  'updated_at': row.updatedAt.toIso8601String(),
  'created_at': row.createdAt.toIso8601String(),
};

CoursesCompanion courseFromServer(Map<String, Object?> row) =>
    CoursesCompanion.insert(
      id: row['id']! as String,
      profileId: row['profile_id']! as String,
      l2: row['l2']! as String,
      pairPack: row['pair_pack']! as String,
      levelEstimates: Value(row['level_estimates']! as Map<String, Object?>),
      vocabEstimate: Value(row['vocab_estimate'] as int?),
      fsrsParams: Value(row['fsrs_params'] as Map<String, Object?>?),
      desiredRetention: Value((row['desired_retention']! as num).toDouble()),
      active: Value(row['active']! as bool),
      updatedAt: Value(_utc(row['updated_at'])),
      serverSeq: Value(row['server_seq'] as int?),
      createdAt: Value(_utc(row['created_at'])),
    );

Map<String, Object?> courseToServer(CourseRow row) => {
  'id': row.id,
  'profile_id': row.profileId,
  'l2': row.l2,
  'pair_pack': row.pairPack,
  'level_estimates': row.levelEstimates,
  'vocab_estimate': row.vocabEstimate,
  'fsrs_params': row.fsrsParams,
  'desired_retention': row.desiredRetention,
  'active': row.active,
  'updated_at': row.updatedAt.toIso8601String(),
  'created_at': row.createdAt.toIso8601String(),
};
