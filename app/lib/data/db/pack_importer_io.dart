import 'dart:convert';
import 'dart:io';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/pack_info.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:drift/native.dart' show SqliteException;

/// Imports a pack through SQLite itself: the file is attached to the local
/// database and its rows are copied as they are, in one transaction.
class PlatformPackImporter implements PackImporter {
  const new(this._db);

  final AppDatabase _db;

  @override
  Future<Result<void, PackFailure>> import(
    Uint8List bytes,
    PackInfo pack,
  ) async {
    final directory = await Directory.systemTemp.createTemp('dilbaz_pack');
    final file = File('${directory.path}${Platform.pathSeparator}pack.sqlite');
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await _importFile(file.path, pack);
    } on FileSystemException {
      return const Err(PackFailure.unknown);
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Future<Result<void, PackFailure>> _importFile(
    String path,
    PackInfo pack,
  ) async {
    var attached = false;
    try {
      await _db.customStatement('ATTACH DATABASE ? AS pack', [path]);
      attached = true;
      final format = await _db
          .customSelect('PRAGMA pack.user_version')
          .map((row) => row.read<int>('user_version'))
          .getSingle();
      if (format != PackImporter.formatVersion) {
        return const Err(PackFailure.unsupported);
      }
      final meta = <String, Object?>{
        for (final row
            in await _db
                .customSelect('SELECT key, value FROM pack.pack_meta')
                .get())
          row.read<String>('key'): jsonDecode(row.read<String>('value')),
      };
      final failure = _check(meta, pack);
      if (failure != null) return Err(failure);

      final inPack = {
        for (final row
            in await _db
                .customSelect(
                  "SELECT name FROM pack.sqlite_master WHERE type = 'table'",
                )
                .get())
          row.read<String>('name'),
      };
      await _db.transaction(() => _replace(pack, meta, inPack));
      _db.notifyUpdates({
        for (final table in [..._contentTables, _db.contentPacks])
          TableUpdate.onTable(table),
      });
      return const Ok(null);
    } on SqliteException {
      // Not a pack file, or not the tables this app expects.
      return const Err(PackFailure.damaged);
    } on DriftRemoteException {
      // The same, when the database runs in a background isolate.
      return const Err(PackFailure.damaged);
    } finally {
      if (attached) await _db.customStatement('DETACH DATABASE pack');
    }
  }

  List<TableInfo<Table, Object?>> get _contentTables => [
    _db.contentItems,
    _db.contentLinks,
    _db.contentForms,
    _db.contentTexts,
    _db.contentTasks,
    _db.contentPairEntries,
  ];

  /// What is wrong with the pack for this app, if anything.
  PackFailure? _check(Map<String, Object?> meta, PackInfo pack) {
    final manifest = meta['manifest'];
    if (manifest is! Map<String, Object?> || manifest['id'] != pack.id) {
      return PackFailure.damaged;
    }
    final needs = manifest['min_engine_version'];
    if (needs is num && needs > engineVersion) return PackFailure.unsupported;
    // The pack's own examples must come out right with this engine.
    final normalization = meta['normalization'];
    if (normalization is Map<String, Object?>) {
      final rules = NormalizationRules.fromJson(normalization);
      final normalizer = Normalizer(rules);
      for (final example in rules.tests) {
        if (normalizer.normalize(example.first) != example.last) {
          return PackFailure.unsupported;
        }
      }
    }
    return null;
  }

  /// Replaces the content of the pack's family with the attached file's.
  Future<void> _replace(
    PackInfo pack,
    Map<String, Object?> meta,
    Set<String> inPack,
  ) async {
    final family = _db.select(_db.contentPacks)
      ..where(
        (t) =>
            t.kind.equals(pack.kind) &
            t.l2.equals(pack.l2) &
            (pack.l1 == null ? t.l1.isNull() : t.l1.equals(pack.l1!)),
      );
    final replaced = {
      pack.id,
      for (final row in await family.get()) row.packId,
    };
    final marks = List.filled(replaced.length, '?').join(', ');
    for (final table in _contentTables) {
      final name = table.actualTableName;
      await _db.customStatement(
        'DELETE FROM "$name" WHERE pack_id IN ($marks)',
        [...replaced],
      );
      if (!inPack.contains(name)) continue;
      final columns = [for (final column in table.$columns) '"${column.name}"']
          .join(', ');
      await _db.customStatement(
        'INSERT INTO "$name" ($columns) SELECT $columns FROM pack."$name"',
      );
    }
    await (_db.delete(
      _db.contentPacks,
    )..where((t) => t.packId.isIn(replaced))).go();
    await _db
        .into(_db.contentPacks)
        .insert(
          ContentPacksCompanion.insert(
            packId: pack.id,
            kind: pack.kind,
            l2: pack.l2,
            l1: Value(pack.l1),
            version: pack.version,
            manifest: meta,
            checksum: pack.checksum,
            importedAt: DateTime.now().toUtc(),
          ),
        );
  }
}
