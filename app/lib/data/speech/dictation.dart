import 'dart:async';

import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/device_recognizer.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';

/// Why nothing was written down; each maps to a calm text, and the
/// learner can type instead.
enum DictationFailure {
  /// The system did not let the app use the microphone.
  permission,

  /// Neither the device nor the server can recognize the language now.
  unavailable,
  network,

  /// The free quota of the server's recognizer is spent.
  quota,
  busy,
  nothingHeard,
  unknown,
}

/// Writes down what the learner says in their own language (A19, docs/08
/// §3.1, S2): on the device where it can, else recorded and sent to the
/// `speech` function.
abstract interface class Dictation {
  /// Starts listening.
  Future<Result<void, DictationFailure>> start();

  /// Stops and hands over what was said.
  Future<Result<String, DictationFailure>> stop();

  /// Throws away what is being said.
  Future<void> cancel();
}

class DeviceFirstDictation implements Dictation {
  new(
    this._device,
    this._recorder,
    this._speech, {
    this._language = 'tr',
    this._finalWait = const Duration(seconds: 3),
  });

  final DeviceRecognizer _device;
  final AnswerRecorder _recorder;
  final SpeechRepository _speech;
  final String _language;

  /// How long [stop] waits for the device's last words.
  final Duration _finalWait;

  /// Longest capture.
  static const limit = Duration(seconds: 30);

  bool? _onDevice;
  var _words = '';
  DeviceRecognitionError? _error;
  Completer<void>? _done;

  @override
  Future<Result<void, DictationFailure>> start() async {
    _words = '';
    _error = null;
    final finished = _done = Completer<void>();
    final onDevice = _onDevice ??= await _device.supports(_language);
    if (onDevice) {
      await _device.listen(
        language: _language,
        listenFor: limit,
        onWords: (words, {required done}) {
          _words = words;
          if (done && !finished.isCompleted) finished.complete();
        },
        onError: (error) {
          _error = error;
          if (!finished.isCompleted) finished.complete();
        },
      );
      return const Ok(null);
    }
    return switch (await _recorder.start()) {
      Ok() => const Ok(null),
      Err(error: RecordFailure.permission) => const Err(
        DictationFailure.permission,
      ),
      Err() => const Err(DictationFailure.unavailable),
    };
  }

  @override
  Future<Result<String, DictationFailure>> stop() async {
    if (_onDevice ?? false) {
      await _device.stop();
      await _done?.future.timeout(_finalWait, onTimeout: () {});
      final words = _words.trim();
      if (words.isNotEmpty) return Ok(words);
      return Err(switch (_error) {
        DeviceRecognitionError.permission => DictationFailure.permission,
        DeviceRecognitionError.network => DictationFailure.network,
        DeviceRecognitionError.other => DictationFailure.unavailable,
        DeviceRecognitionError.nothingHeard ||
        null => DictationFailure.nothingHeard,
      });
    }
    final audio = await _recorder.stop();
    if (audio == null) return const Err(DictationFailure.nothingHeard);
    final heard = await _speech.transcribe(audio, lang: _language);
    return switch (heard) {
      Ok(value: final transcript) when transcript.text.trim().isNotEmpty => Ok(
        transcript.text.trim(),
      ),
      Ok() => const Err(DictationFailure.nothingHeard),
      Err(:final error) => Err(switch (error) {
        SpeechFailure.network => DictationFailure.network,
        SpeechFailure.quota => DictationFailure.quota,
        SpeechFailure.busy => DictationFailure.busy,
        SpeechFailure.unavailable => DictationFailure.unavailable,
        SpeechFailure.badAudio => DictationFailure.nothingHeard,
        SpeechFailure.unknown => DictationFailure.unknown,
      }),
    };
  }

  @override
  Future<void> cancel() async {
    if (_onDevice ?? false) {
      await _device.cancel();
    } else {
      await _recorder.cancel();
    }
  }
}
