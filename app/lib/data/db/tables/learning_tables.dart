import 'package:dilbaz_app/data/db/converters.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:drift/drift.dart';

@DataClassName('PersonalItemRow')
class PersonalItems extends Table with UpdatedAtColumn, SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get courseId => text()();
  TextColumn get kind => text()();
  TextColumn get textL2 => text()();
  TextColumn get lemmas => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get cefr => text().nullable()();
  TextColumn get source => text()();
  TextColumn get glossL1 => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get variants => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get audioPath => text().nullable()();
  BoolColumn get deprecated => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// FSRS state of one card (learner × item × mode). Timestamps are UTC.
@DataClassName('CardRow')
@TableIndex(name: 'cards_profile_due', columns: {#profileId, #due})
class Cards extends Table with UpdatedAtColumn, SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get courseId => text()();
  TextColumn get itemRef => text()();
  TextColumn get mode => text()();
  IntColumn get fsrsCardId => integer()();
  IntColumn get state => integer()();
  IntColumn get step => integer().nullable()();
  RealColumn get stability => real().nullable()();
  RealColumn get difficulty => real().nullable()();
  DateTimeColumn get due => dateTime()();
  DateTimeColumn get lastReview => dateTime().nullable()();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  BoolColumn get suspended => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {profileId, itemRef, mode},
  ];
}

/// Immutable attempt log (I-03): rows are only ever inserted.
@DataClassName('AttemptRow')
@TableIndex(name: 'attempts_card', columns: {#cardId})
@TableIndex(
  name: 'attempts_profile_time',
  columns: {#profileId, #createdAtClient},
)
class Attempts extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get courseId => text()();
  TextColumn get deviceId => text()();
  TextColumn get activity => text()();
  TextColumn get itemRef => text().nullable()();
  TextColumn get cardId => text().nullable()();
  TextColumn get taskRef => text().nullable()();
  TextColumn get textRef => text().nullable()();
  TextColumn get parentAttemptId => text().nullable()();
  TextColumn get prompt => text().map(const JsonObjectConverter())();
  TextColumn get response => text().map(const JsonObjectConverter())();
  TextColumn get verdict => text().nullable()();
  BoolColumn get targetOk => boolean().nullable()();
  TextColumn get errorTags => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  IntColumn get hintsUsed => integer().withDefault(const Constant(0))();
  IntColumn get hintMaxLevel => integer().withDefault(const Constant(0))();
  IntColumn get rating => integer().nullable()();
  IntColumn get latencyMs => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get cardStateAfter =>
      text().map(const JsonObjectConverter()).nullable()();
  TextColumn get llm => text().map(const JsonObjectConverter()).nullable()();
  TextColumn get experiment =>
      text().map(const JsonObjectConverter()).nullable()();
  DateTimeColumn get createdAtClient => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Information that arrives after an attempt (the attempt stays immutable).
@DataClassName('AttemptAmendmentRow')
class AttemptAmendments extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get attemptId => text()();
  TextColumn get profileId => text()();
  TextColumn get kind => text()();
  TextColumn get payload => text().map(const JsonObjectConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
