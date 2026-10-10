import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/pack_info.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';

/// Where there is no file system (web), packs cannot be imported yet.
class PlatformPackImporter implements PackImporter {
  // The parameter keeps the constructor the same on every platform.
  // ignore: avoid_unused_constructor_parameters
  const new(AppDatabase database);

  @override
  Future<Result<void, PackFailure>> import(
    Uint8List bytes,
    PackInfo pack,
  ) async => const Err(PackFailure.unsupported);
}
