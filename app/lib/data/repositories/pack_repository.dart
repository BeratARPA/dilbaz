import 'package:crypto/crypto.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/daos/content_dao.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/pack_info.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';

/// Keeps the local content up to date with the published packs
/// (docs/11-language-packs.md §5).
class PackRepository {
  const new({
    required this._remote,
    required this._importer,
    required this._content,
  });

  final PackRemote _remote;
  final PackImporter _importer;
  final ContentDao _content;

  static const _target = 'target';
  static const _pair = 'pair';

  /// Whether both packs of a course are on the device.
  Future<bool> hasContent({required String l2, required String l1}) async {
    final local = await _content.packs();
    return local.any((p) => p.kind == _target && p.l2 == l2) &&
        local.any((p) => p.kind == _pair && p.l2 == l2 && p.l1 == l1);
  }

  /// Downloads, checks and imports the newest published target pack of
  /// [l2] and pair pack of [l1]–[l2], unless the device has them already.
  /// Gives the ids of the packs it imported.
  Future<Result<List<String>, PackFailure>> sync({
    required String l2,
    required String l1,
  }) async {
    final List<PackInfo> published;
    switch (await _remote.published()) {
      case Ok(:final value):
        published = value;
      case Err(:final error):
        return Err(error);
    }
    final target = _newest(
      published.where((p) => p.kind == _target && p.l2 == l2),
    );
    final pair = _newest(
      published.where((p) => p.kind == _pair && p.l2 == l2 && p.l1 == l1),
    );
    if (target == null || pair == null) return const Err(PackFailure.missing);

    final local = {
      for (final row in await _content.packs()) row.packId: row.checksum,
    };
    final imported = <String>[];
    for (final pack in [target, pair]) {
      if (local[pack.id] == pack.checksum) continue;
      switch (await _remote.download(pack)) {
        case Err(:final error):
          return Err(error);
        case Ok(value: final bytes):
          if ('sha256:${sha256.convert(bytes)}' != pack.checksum) {
            return const Err(PackFailure.damaged);
          }
          if (await _importer.import(bytes, pack) case Err(:final error)) {
            return Err(error);
          }
          imported.add(pack.id);
      }
    }
    return Ok(imported);
  }

  static PackInfo? _newest(Iterable<PackInfo> packs) => packs.fold(
    null,
    (best, pack) => best == null || pack.version > best.version ? pack : best,
  );
}
