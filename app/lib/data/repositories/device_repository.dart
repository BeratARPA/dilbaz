import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// This installation's identity (docs/13-data-model.md §2.6 `devices`):
/// every attempt and session names the device it was made on.
abstract interface class DeviceRepository {
  /// The id of this device for [userId]'s rows; made on first use.
  Future<String> deviceId(String userId);
}

String _uuidV7() => const Uuid().v7();

class DriftDeviceRepository implements DeviceRepository {
  new(
    this._db, {
    this._now = nowUtc,
    this._newId = _uuidV7,
    this._platform = _currentPlatform,
  });

  final AppDatabase _db;
  final DateTime Function() _now;
  final String Function() _newId;
  final String Function() _platform;

  static String _currentPlatform() =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;

  @override
  Future<String> deviceId(String userId) => _db.transaction(() async {
    final known =
        await (_db.select(_db.devices)
              ..where((t) => t.profileId.equals(userId))
              ..orderBy([(t) => OrderingTerm(expression: t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (known != null) return known.id;
    final id = _newId();
    await _db
        .into(_db.devices)
        .insert(
          DevicesCompanion.insert(
            id: id,
            profileId: userId,
            platform: _platform(),
            createdAt: Value(_now()),
          ),
        );
    return id;
  });
}
