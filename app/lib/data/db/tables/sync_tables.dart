import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:drift/drift.dart';

/// Local writes waiting to be pushed (docs/13-data-model.md §8).
///
/// Entries only name the row; the push reads the row's current state, so
/// several updates of the same state row collapse into one push.
@DataClassName('OutboxEntry')
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get targetTable => text()();
  TextColumn get rowId => text()();

  /// `insert` for event tables, `upsert` for state tables.
  TextColumn get op => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(nowUtc)();

  /// Failed push attempts so far; drives the exponential backoff.
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  /// Error code of the last failure; never personal text.
  TextColumn get lastError => text().nullable()();
}

/// This installation, one row per signed-in profile (docs/13-data-model.md
/// §2.6 `devices`): attempts and sessions name the device they were made on.
@DataClassName('DeviceRow')
class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get platform => text()();
  TextColumn get appVersion => text().nullable()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(nowUtc)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Pull cursor per signed-in profile.
@DataClassName('SyncStateRow')
class SyncState extends Table {
  TextColumn get profileId => text()();
  IntColumn get lastServerSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {profileId};
}
