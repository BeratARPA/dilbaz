import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:record/record.dart';

/// Where there is no file system (web), answers cannot be recorded yet.
class PlatformAnswerRecorder implements AnswerRecorder {
  // The parameter keeps the constructor the same on every platform.
  // ignore: avoid_unused_constructor_parameters
  const new(AudioRecorder recorder);

  @override
  Future<Result<void, RecordFailure>> start({
    bool pronunciation = false,
  }) async => const Err(RecordFailure.unsupported);

  @override
  Future<RecordedAudio?> stop() async => null;

  @override
  Future<void> cancel() async {}

  @override
  Stream<double> level() => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
