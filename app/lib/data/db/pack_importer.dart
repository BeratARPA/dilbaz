import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/pack_importer_stub.dart'
    if (dart.library.io) 'package:dilbaz_app/data/db/pack_importer_io.dart';
import 'package:dilbaz_app/data/repositories/pack_info.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';

/// Brings a downloaded pack file into the local content tables
/// (docs/11-language-packs.md §5).
abstract interface class PackImporter {
  /// The importer of this platform.
  factory(AppDatabase database) = PlatformPackImporter;

  /// Format of pack files this app reads (`PRAGMA user_version`).
  static const formatVersion = 1;

  /// Checks the file in [bytes] and replaces the content of [pack]'s
  /// family (same kind and languages) with it, all or nothing.
  Future<Result<void, PackFailure>> import(Uint8List bytes, PackInfo pack);
}
