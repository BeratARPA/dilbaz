import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/pack_info.dart';

/// Why content could not be brought up to date; each maps to a calm UI text.
enum PackFailure {
  /// No connection.
  network,

  /// The registry has no published pack for the course.
  missing,

  /// A downloaded file does not match its checksum.
  damaged,

  /// The pack needs a newer app: unknown file format or engine version.
  unsupported,

  unknown,
}

/// The server side of content packs: the registry and the pack files.
abstract interface class PackRemote {
  /// The published packs.
  Future<Result<List<PackInfo>, PackFailure>> published();

  /// The bytes of [pack]'s file.
  Future<Result<Uint8List, PackFailure>> download(PackInfo pack);
}
