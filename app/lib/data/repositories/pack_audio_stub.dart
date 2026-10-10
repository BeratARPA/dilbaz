import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/pack_audio.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';

/// Where there is no file system (web), clips cannot be kept yet.
class PlatformPackAudio implements PackAudio {
  const new(
    // The parameters keep the constructor the same on every platform.
    // ignore: avoid_unused_constructor_parameters
    PackAudioRemote remote, {
    // The same here.
    // ignore: avoid_unused_constructor_parameters
    required Future<String> Function() directory,
  });

  @override
  Future<Result<String, PackFailure>> file(String clip) async =>
      const Err(PackFailure.unsupported);
}
