import 'package:drift/drift.dart';

DateTime nowUtc() => DateTime.now().toUtc();

/// Columns of every synced user table (docs/13-data-model.md §1, §8).
///
/// `server_seq` is null until the server has assigned one. `pending_push`
/// marks rows written locally; local writes set it in the same transaction
/// as their outbox entry. Rows pulled from the server keep the default.
mixin SyncColumns on Table {
  IntColumn get serverSeq => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(nowUtc)();
  BoolColumn get pendingPush => boolean().withDefault(const Constant(false))();
}

/// Last-writer-wins timestamp of state tables (docs/12-architecture.md §6).
mixin UpdatedAtColumn on Table {
  DateTimeColumn get updatedAt => dateTime().clientDefault(nowUtc)();
}
