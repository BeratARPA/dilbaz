import 'dart:io';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/pack_audio.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';

/// Keeps clips as files under the app's own directory, laid out as in the
/// bucket.
class PlatformPackAudio implements PackAudio {
  const new(this._remote, {required this._directory});

  final PackAudioRemote _remote;
  final Future<String> Function() _directory;

  @override
  Future<Result<String, PackFailure>> file(String clip) async {
    final file = File('${await _directory()}/$clip');
    try {
      if (file.existsSync() && file.lengthSync() > 0) return Ok(file.path);
      switch (await _remote.download(clip)) {
        case Err(:final error):
          return Err(error);
        case Ok(value: final bytes):
          await file.parent.create(recursive: true);
          // Written under another name first, so that a clip cut short by
          // a closed app is never taken for a whole one.
          final partial = File('${file.path}.part');
          await partial.writeAsBytes(bytes, flush: true);
          await partial.rename(file.path);
          return Ok(file.path);
      }
    } on FileSystemException {
      return const Err(PackFailure.unknown);
    }
  }
}
