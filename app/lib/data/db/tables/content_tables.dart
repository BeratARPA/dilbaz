import 'package:dilbaz_app/data/db/converters.dart';
import 'package:drift/drift.dart';

// Read-only language-pack content (docs/11-language-packs.md §5). Rows are
// replaced atomically when a pack version is imported. Kind-specific fields
// live in `data` so that pack format additions do not need migrations.

@DataClassName('ContentPackRow')
class ContentPacks extends Table {
  TextColumn get packId => text()();
  TextColumn get kind => text()();
  TextColumn get l2 => text()();
  TextColumn get l1 => text().nullable()();
  RealColumn get version => real()();
  TextColumn get manifest => text().map(const JsonObjectConverter())();
  TextColumn get checksum => text()();
  DateTimeColumn get importedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {packId};
}

/// Word senses, chunks, sentences, grammar points, sounds and patterns.
@DataClassName('ContentItemRow')
class ContentItems extends Table {
  TextColumn get key => text()();
  TextColumn get packId => text()();
  TextColumn get kind => text()();
  TextColumn get level => text()();
  TextColumn get textL2 => text().nullable()();
  TextColumn get lemmas => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get targets => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get grammar => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  IntColumn get rank => integer().nullable()();
  BoolColumn get deprecated => boolean().withDefault(const Constant(false))();
  TextColumn get data => text()
      .map(const JsonObjectConverter())
      .withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('ContentLinkRow')
class ContentLinks extends Table {
  TextColumn get fromKey => text()();
  TextColumn get toKey => text()();
  TextColumn get type => text()();
  TextColumn get packId => text()();

  @override
  Set<Column<Object>> get primaryKey => {fromKey, toKey, type};
}

/// Surface form → lemma table used for runtime lemmatization.
@DataClassName('ContentFormRow')
class ContentForms extends Table {
  TextColumn get form => text()();
  TextColumn get lemma => text()();
  TextColumn get packId => text()();

  @override
  Set<Column<Object>> get primaryKey => {form, lemma};
}

/// Reading and listening texts and dialogues.
@DataClassName('ContentTextRow')
class ContentTexts extends Table {
  TextColumn get key => text()();
  TextColumn get packId => text()();
  TextColumn get kind => text()();
  TextColumn get level => text()();
  TextColumn get lemmas => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get data => text()
      .map(const JsonObjectConverter())
      .withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Speaking, role-play, information-gap, writing and mediation tasks.
@DataClassName('ContentTaskRow')
class ContentTasks extends Table {
  TextColumn get key => text()();
  TextColumn get packId => text()();
  TextColumn get kind => text()();
  TextColumn get level => text()();
  TextColumn get data => text()
      .map(const JsonObjectConverter())
      .withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Language-pair entries: glosses, contrast notes, error tags, variants,
/// can-do summaries, task instructions and learning notes.
@DataClassName('ContentPairEntryRow')
class ContentPairEntries extends Table {
  TextColumn get kind => text()();
  TextColumn get key => text()();
  TextColumn get packId => text()();
  TextColumn get data => text().map(const JsonObjectConverter())();

  @override
  Set<Column<Object>> get primaryKey => {kind, key};
}
