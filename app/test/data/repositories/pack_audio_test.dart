import 'dart:io';
import 'dart:typed_data';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/repositories/pack_audio.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bucket files by path.
class FakeAudioRemote implements PackAudioRemote {
  final files = <String, Uint8List>{};
  final downloads = <String>[];
  PackFailure? failure;

  @override
  Future<Result<Uint8List, PackFailure>> download(String path) async {
    downloads.add(path);
    final failure = this.failure;
    if (failure != null) return Err(failure);
    final file = files[path];
    return file == null ? const Err(PackFailure.missing) : Ok(file);
  }
}

void main() {
  late Directory directory;
  late FakeAudioRemote remote;
  late PackAudio audio;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dilbaz_clips');
    remote = FakeAudioRemote()
      ..files['en/1/v1/a.mp3'] = Uint8List.fromList([1, 2, 3]);
    audio = PackAudio(remote, directory: () async => directory.path);
  });

  tearDown(() => directory.delete(recursive: true));

  group('PackAudio (docs/11-language-packs.md §5)', () {
    test('fetches a clip on first use and keeps it', () async {
      final first = await audio.file('en/1/v1/a.mp3');
      final path = (first as Ok<String, PackFailure>).value;
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
      expect(path, endsWith('en/1/v1/a.mp3'));

      final again = await audio.file('en/1/v1/a.mp3');
      expect((again as Ok<String, PackFailure>).value, path);
      expect(remote.downloads, ['en/1/v1/a.mp3']);
      expect(File('$path.part').existsSync(), isFalse);
    });

    test('a clip cut short is fetched again', () async {
      final kept = File('${directory.path}/en/1/v1/a.mp3')
        ..createSync(recursive: true);
      File('${kept.path}.part').writeAsBytesSync([1]);

      final result = await audio.file('en/1/v1/a.mp3');

      expect(result, isA<Ok<String, PackFailure>>());
      expect(kept.readAsBytesSync(), [1, 2, 3]);
      expect(remote.downloads, hasLength(1));
    });

    test('passes on why a clip could not be fetched', () async {
      expect(
        (await audio.file('en/1/v1/none.mp3') as Err).error,
        PackFailure.missing,
      );
      remote.failure = PackFailure.network;
      expect(
        (await audio.file('en/1/v1/a.mp3') as Err).error,
        PackFailure.network,
      );
      expect(Directory('${directory.path}/en').existsSync(), isFalse);
    });

    test('a place it cannot write to is an unknown failure', () async {
      // A file where the folder of the clip should be.
      File('${directory.path}/en').writeAsStringSync('in the way');

      expect(
        (await audio.file('en/1/v1/a.mp3') as Err).error,
        PackFailure.unknown,
      );
    });
  });

  group('SupabasePackAudioRemote', () {
    SupabasePackAudioRemote remoteWith(MockClientHandler handler) =>
        SupabasePackAudioRemote(
          SupabaseClient(
            'https://example.supabase.co',
            'sb_publishable_test',
            httpClient: MockClient(handler),
          ),
        );

    test('downloads from the pack-audio bucket', () async {
      late Request seen;
      final remote = remoteWith((request) async {
        seen = request;
        return Response.bytes([7, 8], 200, request: request);
      });

      final result = await remote.download('en/1/v1/a.mp3');

      expect((result as Ok<Uint8List, PackFailure>).value, [7, 8]);
      expect(seen.url.path, '/storage/v1/object/pack-audio/en/1/v1/a.mp3');
    });

    test('a missing clip and no connection are told apart', () async {
      final missing = remoteWith(
        (request) async => Response(
          '{"statusCode":"404","error":"not_found",'
          '"message":"Object not found"}',
          404,
          request: request,
        ),
      );
      expect(
        (await missing.download('en/1/v1/none.mp3') as Err).error,
        PackFailure.missing,
      );
      final offline = remoteWith(
        (request) async => throw ClientException('offline'),
      );
      expect(
        (await offline.download('en/1/v1/a.mp3') as Err).error,
        PackFailure.network,
      );
    });
  });
}
