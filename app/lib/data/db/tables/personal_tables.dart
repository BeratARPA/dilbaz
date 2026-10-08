import 'package:dilbaz_app/data/db/converters.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:drift/drift.dart';

/// "Söyleyemediklerim" entries (A19).
@DataClassName('GapEntryRow')
@TableIndex(name: 'gap_entries_profile_status', columns: {#profileId, #status})
class GapEntries extends Table with UpdatedAtColumn, SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get courseId => text()();
  TextColumn get l1Text => text()();
  TextColumn get audioPath => text().nullable()();
  TextColumn get context => text()();
  TextColumn get note => text().nullable()();
  TextColumn get suggestion =>
      text().map(const JsonObjectConverter()).nullable()();
  TextColumn get status => text().withDefault(const Constant('new'))();
  TextColumn get personalItemIds => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Task and test recordings. `audio_path` becomes null when retention
/// deletes the audio (docs/13-data-model.md §7).
@DataClassName('RecordingRow')
class Recordings extends Table with UpdatedAtColumn, SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get courseId => text()();
  TextColumn get taskRef => text().nullable()();
  TextColumn get attemptId => text().nullable()();
  TextColumn get audioPath => text().nullable()();
  IntColumn get durationMs => integer()();
  TextColumn get asr => text().map(const JsonObjectConverter()).nullable()();
  TextColumn get annotation =>
      text().map(const JsonObjectConverter()).nullable()();
  TextColumn get metrics =>
      text().map(const JsonObjectConverter()).nullable()();
  TextColumn get outcome => text().nullable()();
  BoolColumn get isAssessment => boolean().withDefault(const Constant(false))();
  TextColumn get assessmentId => text().nullable()();
  BoolColumn get keep => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AssessmentRow')
class Assessments extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get courseId => text()();
  TextColumn get kind => text()();
  TextColumn get results => text().map(const JsonObjectConverter())();
  TextColumn get levelEstimates =>
      text().map(const JsonObjectConverter()).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WritingRow')
class Writings extends Table with UpdatedAtColumn, SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get courseId => text()();
  TextColumn get taskRef => text()();
  TextColumn get drafts => text()
      .map(const JsonArrayConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get feedback =>
      text().map(const JsonObjectConverter()).nullable()();
  TextColumn get finalText => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Study sessions, written once when the session ends.
@DataClassName('SessionRow')
class Sessions extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get courseId => text()();
  TextColumn get deviceId => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get planned =>
      text().map(const JsonObjectConverter()).nullable()();
  TextColumn get done => text().map(const JsonObjectConverter()).nullable()();
  IntColumn get activeMs => integer().withDefault(const Constant(0))();
  TextColumn get strandMs => text()
      .map(const JsonObjectConverter())
      .withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Media diary. `day` is a local calendar date, `YYYY-MM-DD`.
@DataClassName('MediaLogRow')
class MediaLogs extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get courseId => text()();
  TextColumn get kind => text()();
  TextColumn get title => text().nullable()();
  IntColumn get minutes => integer()();
  TextColumn get subtitles => text().nullable()();
  BoolColumn get withPartner => boolean().withDefault(const Constant(false))();
  TextColumn get day => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SubtitleImportRow')
class SubtitleImports extends Table with UpdatedAtColumn, SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get courseId => text()();
  TextColumn get title => text()();
  TextColumn get filePath => text()();
  RealColumn get coverage => real().nullable()();
  TextColumn get unknown =>
      text().map(const JsonObjectConverter()).nullable()();
  TextColumn get status => text().withDefault(const Constant('imported'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// "Bu içerikte hata var" (docs/10-content-pipeline.md §8): what the
/// learner reported about the content. Only the maintainers change
/// `status`, on the server.
@DataClassName('ContentReportRow')
class ContentReports extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get itemRef => text()();
  TextColumn get reason => text()();
  TextColumn get note => text().nullable()();
  TextColumn get context => text()
      .map(const JsonObjectConverter())
      .withDefault(const Constant('{}'))();
  TextColumn get status => text().withDefault(const Constant('open'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
