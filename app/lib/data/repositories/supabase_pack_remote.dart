import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/pack_info.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the `packs` registry and the private `packs` bucket. Row level
/// security shows a signed-in user published packs only
/// (docs/13-data-model.md §4 and §6).
class SupabasePackRemote implements PackRemote {
  const new(this._client);

  final SupabaseClient _client;

  static const _table = 'packs';

  @override
  Future<Result<List<PackInfo>, PackFailure>> published() async {
    try {
      // No retries: the app opens with the content it has, and asks again
      // next time (the client would otherwise back off for seconds).
      final rows = await _client
          .from(_table)
          .select('id, kind, l2, l1, version, checksum, storage_path')
          .retry(enabled: false);
      return Ok([for (final row in rows) PackInfo.fromJson(row)]);
    } on PostgrestException {
      return const Err(PackFailure.unknown);
    } on ClientException {
      return const Err(PackFailure.network);
    }
  }

  @override
  Future<Result<Uint8List, PackFailure>> download(PackInfo pack) async {
    final (bucket, path) = splitStoragePath(pack.storagePath);
    try {
      return Ok(await _client.storage.from(bucket).download(path));
    } on StorageException catch (error) {
      return Err(downloadFailure(error));
    } on ClientException {
      return const Err(PackFailure.network);
    }
  }
}

/// `packs/en@1.sqlite` → bucket `packs`, path `en@1.sqlite`.
(String bucket, String path) splitStoragePath(String storagePath) {
  final slash = storagePath.indexOf('/');
  return (storagePath.substring(0, slash), storagePath.substring(slash + 1));
}

/// Maps a failed download. The storage client reports an HTTP answer with
/// its status code; where it wraps another error, such as no connection,
/// the status is the name of that error's type.
PackFailure downloadFailure(StorageException error) =>
    switch (int.tryParse(error.statusCode ?? '')) {
      null => PackFailure.network,
      400 || 404 => PackFailure.missing,
      _ => PackFailure.unknown,
    };
