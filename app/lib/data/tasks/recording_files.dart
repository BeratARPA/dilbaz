import 'dart:async';
import 'dart:math';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:dilbaz_app/data/sync/sync_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_store.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a recording's audio did not cross.
enum AudioFailure {
  /// The server could not be reached.
  network,

  /// The server refused it, or does not have it.
  refused,
}

/// The private audio bucket (docs/13-data-model.md §6 `audio-private`):
/// the learner's own folder only (I-18).
abstract interface class AudioRemote {
  Future<Result<void, AudioFailure>> upload(String path, Uint8List bytes);

  Future<Result<Uint8List, AudioFailure>> download(String path);

  /// Every audio file in the folder of [userId] (`{uid}/{yyyy}/{mm}/…`).
  Future<Result<List<String>, AudioFailure>> listOwn(String userId);

  /// Removes [paths]; files already gone are no trouble.
  Future<Result<void, AudioFailure>> remove(List<String> paths);
}

class SupabaseAudioRemote implements AudioRemote {
  const new(this._client);

  final SupabaseClient _client;

  static const bucket = 'audio-private';

  /// A recording is under a megabyte; a call that takes longer has gone
  /// wrong.
  static const wait = Duration(seconds: 60);

  @override
  Future<Result<void, AudioFailure>> upload(String path, Uint8List bytes) =>
      _call(
        () => _client.storage
            .from(bucket)
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: recordingContentType(path),
                upsert: true,
              ),
            ),
        (_) {},
      );

  @override
  Future<Result<Uint8List, AudioFailure>> download(String path) => _call(
    () => _client.storage.from(bucket).download(path),
    (bytes) => bytes,
  );

  @override
  Future<Result<List<String>, AudioFailure>> listOwn(String userId) =>
      _call(() => _walk(userId, 2), (paths) => paths);

  /// The files under [prefix], down [depth] more folders (years, months).
  Future<List<String>> _walk(String prefix, int depth) async {
    final found = <String>[];
    for (var offset = 0; ; offset += _page) {
      final objects = await _client.storage
          .from(bucket)
          .list(
            path: prefix,
            searchOptions: SearchOptions(limit: _page, offset: offset),
          );
      for (final object in objects) {
        final path = '$prefix/${object.name}';
        // A folder has no id.
        if (object.id != null) {
          found.add(path);
        } else if (depth > 0) {
          found.addAll(await _walk(path, depth - 1));
        }
      }
      if (objects.length < _page) return found;
    }
  }

  static const _page = 1000;

  @override
  Future<Result<void, AudioFailure>> remove(List<String> paths) =>
      _call(() async {
        for (var start = 0; start < paths.length; start += 100) {
          await _client.storage
              .from(bucket)
              .remove(paths.sublist(start, min(start + 100, paths.length)));
        }
      }, (_) {});

  Future<Result<R, AudioFailure>> _call<T, R>(
    Future<T> Function() call,
    R Function(T value) read,
  ) async {
    try {
      return Ok(read(await call().timeout(wait)));
    } on StorageException {
      return const Err(AudioFailure.refused);
    } on ClientException {
      return const Err(AudioFailure.network);
    } on TimeoutException {
      return const Err(AudioFailure.network);
    }
  }
}

/// The audio of task and test recordings, on this device and on the
/// server (docs/08-speech.md §5.2): it goes up after a sync, and comes down
/// when a recording made on another device is played.
abstract interface class RecordingFiles {
  /// Sends the audio that waits to go up; how many went.
  Future<int> uploadWaiting();

  /// A file to play for [audioPath]: this device's, else fetched from the
  /// server; null when neither has it.
  Future<String?> playable(String audioPath);
}

class DriftRecordingFiles implements RecordingFiles {
  new(this._db, this._store, this._remote, {this._now = nowUtc});

  final AppDatabase _db;
  final RecordingStore _store;
  final AudioRemote _remote;
  final DateTime Function() _now;

  /// The outbox entry of audio waiting to go up.
  static const upload = 'upload';

  @override
  Future<int> uploadWaiting() async {
    final now = _now();
    final due =
        await (_db.select(_db.outbox)
              ..where(
                (t) =>
                    t.op.equals(upload) &
                    (t.nextAttemptAt.isNull() |
                        t.nextAttemptAt.isSmallerOrEqualValue(now)),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.id)]))
            .get();
    var sent = 0;
    for (final entry in due) {
      final row = await (_db.select(
        _db.recordings,
      )..where((t) => t.id.equals(entry.rowId))).getSingleOrNull();
      final path = row?.audioPath;
      final here = path == null ? null : await _store.find(path);
      final bytes = here == null ? null : await _store.read(here);
      if (path == null || bytes == null) {
        // Gone from this device: there is nothing to send.
        await _done(entry);
        continue;
      }
      switch (await _remote.upload(path, bytes)) {
        case Ok():
          await _done(entry);
          sent++;
        case Err(error: AudioFailure.network):
          // Out of reach: the next sync tries again.
          return sent;
        case Err():
          await _later(entry);
      }
    }
    return sent;
  }

  Future<void> _done(OutboxEntry entry) =>
      (_db.delete(_db.outbox)..where((t) => t.id.equals(entry.id))).go();

  Future<void> _later(OutboxEntry entry) {
    final tries = entry.attempts + 1;
    return (_db.update(_db.outbox)..where((t) => t.id.equals(entry.id))).write(
      OutboxCompanion(
        attempts: Value(tries),
        nextAttemptAt: Value(_now().add(DriftSyncRepository.backoff(tries))),
        lastError: Value(AudioFailure.refused.name),
      ),
    );
  }

  @override
  Future<String?> playable(String audioPath) async {
    final here = await _store.find(audioPath);
    if (here != null) return here;
    return switch (await _remote.download(audioPath)) {
      Ok(:final value) => await _store.keepFetched(audioPath, value),
      Err() => null,
    };
  }
}
