import 'package:dilbaz_app/data/db/converters.dart';
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
    Outbox,
    SyncState,
    ContentPacks,
    ContentItems,
    ContentLinks,
    ContentForms,
    ContentTexts,
    ContentTasks,
    ContentPairEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  new(super.e);

  @override
  int get schemaVersion => 1;
}
