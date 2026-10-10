import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/pack_info.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';

import 'pack_fixture.dart';

/// An in-memory registry and bucket.
class FakePackRemote implements PackRemote {
  new([Iterable<BuiltPack> packs = const []]) {
    packs.forEach(publish);
  }

  final _files = <PackInfo, Uint8List>{};

  /// Failure of the registry; null means it answers.
  PackFailure? registryFailure;

  /// Failure of downloads; null means they work.
  PackFailure? downloadFailure;

  /// Ids of the packs downloaded so far.
  final downloaded = <String>[];

  void publish(BuiltPack pack) => _files[pack.info] = pack.bytes;

  @override
  Future<Result<List<PackInfo>, PackFailure>> published() async {
    final failure = registryFailure;
    return failure == null ? Ok([..._files.keys]) : Err(failure);
  }

  @override
  Future<Result<Uint8List, PackFailure>> download(PackInfo pack) async {
    final failure = downloadFailure;
    if (failure != null) return Err(failure);
    downloaded.add(pack.id);
    return Ok(_files[pack]!);
  }
}
