import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/pack_audio_stub.dart'
    if (dart.library.io) 'package:dilbaz_app/data/repositories/pack_audio_io.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/supabase_pack_remote.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The server side of pack audio: the clips of the `pack-audio` bucket.
abstract interface class PackAudioRemote {
  /// The bytes of the clip at [path] in the bucket.
  Future<Result<Uint8List, PackFailure>> download(String path);
}

/// Reads the private `pack-audio` bucket, which any signed-in user may
/// read (docs/13-data-model.md §6).
class SupabasePackAudioRemote implements PackAudioRemote {
  const new(this._client);

  final SupabaseClient _client;

  static const _bucket = 'pack-audio';

  @override
  Future<Result<Uint8List, PackFailure>> download(String path) async {
    try {
      return Ok(await _client.storage.from(_bucket).download(path));
    } on StorageException catch (error) {
      return Err(downloadFailure(error));
    } on ClientException {
      return const Err(PackFailure.network);
    }
  }
}

/// The clips of the language packs on this device: fetched on first use
/// and kept (docs/11-language-packs.md §5).
abstract interface class PackAudio {
  /// The store of this platform; [directory] is where clips are kept.
  factory(
    PackAudioRemote remote, {
    required Future<String> Function() directory,
  }) = PlatformPackAudio;

  /// The local file of [clip] (its path in the bucket), fetched first if
  /// it is not on the device yet.
  Future<Result<String, PackFailure>> file(String clip);
}
