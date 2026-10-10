import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Hands a file to the system's share sheet; the learner picks where it
/// goes (docs/14-security-privacy.md §4, taşınabilirlik).
abstract interface class FileSharer {
  /// True when the learner shared or saved it.
  Future<bool> share({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  });
}

class SharePlusFileSharer implements FileSharer {
  const new();

  @override
  Future<bool> share({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: name, mimeType: mimeType)],
        fileNameOverrides: [name],
      ),
    );
    return result.status == ShareResultStatus.success;
  }
}
