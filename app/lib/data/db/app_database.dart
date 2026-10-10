import 'package:dilbaz_app/data/db/app_database.steps.dart';
import 'package:dilbaz_app/data/db/converters.dart';
import 'package:dilbaz_app/data/db/daos/content_dao.dart';
import 'package:dilbaz_app/data/db/tables/content_tables.dart';
import 'package:dilbaz_app/data/db/tables/identity_tables.dart';
import 'package:dilbaz_app/data/db/tables/learning_tables.dart';
import 'package:dilbaz_app/data/db/tables/personal_tables.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:dilbaz_app/data/db/tables/sync_tables.dart';
import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Local database: the single source of the UI (docs/12-architecture.md §6).
///
/// User tables mirror the server tables (docs/13-data-model.md §2) plus
/// `pending_push`. Server-side foreign keys and CHECK constraints are not
/// repeated locally, so that sync order and server schema evolution never
/// break local inserts; validation happens on the server and in repositories.
@DriftDatabase(
  tables: [
    Profiles,
    Courses,
    PersonalItems,
    Cards,
    Attempts,
    AttemptAmendments,
    GapEntries,
    Recordings,
    Assessments,
    Writings,
    Sessions,
    MediaLogs,
    SubtitleImports,
    ContentReports,
    Outbox,
    SyncState,
    Devices,
    ContentPacks,
    ContentItems,
    ContentLinks,
    ContentForms,
    ContentTexts,
    ContentTasks,
    ContentPairEntries,
  ],
  daos: [ContentDao],
)
class AppDatabase extends _$AppDatabase {
  new(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onUpgrade: _schemaUpgrade);
}

extension on GeneratedDatabase {
  // Outside the class, so that a step cannot read the current schema by
  // mistake: each one brings the database to its own snapshot.
  OnUpgrade get _schemaUpgrade => stepByStep(
    // v2: the device an attempt was made on (F1-16).
    from1To2: (m, schema) => m.createTable(schema.devices),
    // v3: content reports, synced from F1-21.
    from2To3: (m, schema) => m.createTable(schema.contentReports),
  );
}
