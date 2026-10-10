import 'dart:convert';

import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:drift/drift.dart';

/// How two copies of a synced row become one (docs/12-architecture.md §6).
enum SyncMerge {
  /// Rows the device only adds: events (I-03) and content reports, whose
  /// status only the server changes. The server's copy is the row.
  server,

  /// Changed in place: the later `updated_at` wins.
  updatedAt,

  /// Cards: the later `last_review` wins.
  lastReview,
}

/// A table that syncs; its name and columns are the server's. `values`
/// wraps column values for writes to it.
typedef SyncedTable = ({
  TableInfo<Table, Object?> table,
  SyncMerge merge,
  Insertable<Object?> Function(Map<String, Expression> columns) values,
});

/// [table] with its own row type, which drift checks at run time.
SyncedTable _synced<T extends Table, D>(
  TableInfo<T, D> table,
  SyncMerge merge,
) => (table: table, merge: merge, values: RawValuesInsertable<D>.new);

/// The tables `sync_push` and `sync_pull` carry (docs/13-data-model.md §5).
/// Writings, media logs and subtitle imports come with their phases.
List<SyncedTable> syncedTables(AppDatabase db) => [
  _synced(db.profiles, SyncMerge.updatedAt),
  _synced(db.courses, SyncMerge.updatedAt),
  _synced(db.personalItems, SyncMerge.updatedAt),
  _synced(db.cards, SyncMerge.lastReview),
  _synced(db.attempts, SyncMerge.server),
  _synced(db.attemptAmendments, SyncMerge.server),
  _synced(db.gapEntries, SyncMerge.updatedAt),
  _synced(db.recordings, SyncMerge.updatedAt),
  _synced(db.assessments, SyncMerge.server),
  _synced(db.sessions, SyncMerge.server),
  _synced(db.contentReports, SyncMerge.server),
];

/// Local rows to server rows and back, read from the tables' own columns:
/// the local column names are the server's (docs/13-data-model.md §8).
abstract final class SyncRows {
  /// Columns a push leaves out: the server numbers rows itself, and only
  /// this device knows what waits to be sent.
  static const _notSent = {'server_seq', 'pending_push'};

  /// [row] of [table] as the server takes it: times in UTC ISO-8601, JSON
  /// columns as JSON.
  static Map<String, Object?> toServer(
    TableInfo<Table, Object?> table,
    Insertable<Object?> row,
  ) {
    final values = row.toColumns(false);
    return {
      for (final column in table.$columns)
        if (!_notSent.contains(column.name))
          column.name: _json(column, values[column.name]),
    };
  }

  /// A server [row] of [table] as local column values; columns the server
  /// does not send keep their local value or default.
  static Map<String, Expression> toLocal(
    TableInfo<Table, Object?> table,
    Map<String, Object?> row, {
    required bool pending,
  }) => {
    for (final column in table.$columns)
      if (row.containsKey(column.name))
        column.name: _variable(column, row[column.name]),
    'pending_push': Variable<bool>(pending),
  };

  static Object? _json(GeneratedColumn<Object> column, Expression? value) {
    final raw = switch (value) {
      Variable(:final value) => value,
      _ => null,
    };
    return switch (raw) {
      null => null,
      DateTime() => raw.toUtc().toIso8601String(),
      String() when column is GeneratedColumnWithTypeConverter => jsonDecode(
        raw,
      ),
      _ => raw,
    };
  }

  static Variable<Object> _variable(
    GeneratedColumn<Object> column,
    Object? value,
  ) {
    if (value == null) return const Variable(null);
    // Every converted column holds JSON text (converters.dart).
    if (column is GeneratedColumnWithTypeConverter) {
      return Variable<String>(jsonEncode(value));
    }
    return switch (column.type) {
      DriftSqlType.dateTime => Variable<DateTime>(
        DateTime.parse(value as String).toUtc(),
      ),
      DriftSqlType.bool => Variable<bool>(value as bool),
      DriftSqlType.int => Variable<int>((value as num).toInt()),
      DriftSqlType.double => Variable<double>((value as num).toDouble()),
      _ => Variable<String>(value as String),
    };
  }
}
