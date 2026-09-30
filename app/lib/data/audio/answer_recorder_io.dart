import 'dart:io';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/audio/recorder_config.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records to a temporary file, reads it on stop and removes it.
class PlatformAnswerRecorder implements AnswerRecorder {
  new(this._recorder, {Future<Directory> Function()? directory})
    : _directory = directory ?? getTemporaryDirectory;

  final AudioRecorder _recorder;
  final Future<Directory> Function() _directory;
  final RecordSpec _spec = RecorderConfig.speech(web: false);
  final _watch = Stopwatch();
  String? _path;

  @override
  Future<Result<void, RecordFailure>> start() async {
    try {
      if (!await _recorder.hasPermission()) {
        return const Err(RecordFailure.permission);
      }
      final directory = await _directory();
      final path =
          '${directory.path}/answer_${DateTime.now().microsecondsSinceEpoch}'
          '.${_spec.extension}';
      await _recorder.start(_spec.config, path: path);
      _path = path;
      _watch
        ..reset()
        ..start();
      return const Ok(null);
    } on PlatformException {
      return const Err(RecordFailure.device);
    }
  }

  @override
  Future<RecordedAudio?> stop() async {
    if (_path == null) return null;
    _watch.stop();
    try {
      final path = await _recorder.stop() ?? _path!;
      final file = File(path);
      final bytes = await file.readAsBytes();
      await file.delete();
      if (bytes.isEmpty) return null;
      return (
        bytes: bytes,
        contentType: _spec.contentType,
        duration: _watch.elapsed,
      );
    } on PlatformException {
      return null;
    } on FileSystemException {
      return null;
    } finally {
      _path = null;
    }
  }

  @override
  Future<void> cancel() async {
    if (_path == null) return;
    _path = null;
    _watch.stop();
    // The plugin removes the file of a cancelled recording.
    await _recorder.cancel();
  }

  @override
  Stream<double> level() => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((amplitude) => loudness(amplitude.current));

  @override
  Future<void> dispose() => _recorder.dispose();
}
