import 'package:dilbaz_app/data/db/converters.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:drift/drift.dart';

@DataClassName('ProfileRow')
class Profiles extends Table with UpdatedAtColumn, SyncColumns {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get l1 => text().withDefault(const Constant('tr'))();
  TextColumn get uiLocale => text().withDefault(const Constant('tr'))();
  IntColumn get timeBudgetMin => integer().withDefault(const Constant(30))();
  IntColumn get weeklyDaysGoal => integer().withDefault(const Constant(5))();
  TextColumn get anchors => text()
      .map(const JsonArrayConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get quietHours =>
      text().map(const JsonObjectConverter()).nullable()();
  TextColumn get goalText => text().nullable()();
  TextColumn get interests => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get scaffoldOverrides => text()
      .map(const JsonObjectConverter())
      .withDefault(const Constant('{}'))();
  TextColumn get settings => text()
      .map(const JsonObjectConverter())
      .withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CourseRow')
class Courses extends Table with UpdatedAtColumn, SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get l2 => text()();
  TextColumn get pairPack => text()();
  TextColumn get levelEstimates => text()
      .map(const JsonObjectConverter())
      .withDefault(const Constant('{}'))();
  IntColumn get vocabEstimate => integer().nullable()();
  TextColumn get fsrsParams =>
      text().map(const JsonObjectConverter()).nullable()();
  RealColumn get desiredRetention => real().withDefault(const Constant(0.90))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {profileId, l2},
  ];
}
