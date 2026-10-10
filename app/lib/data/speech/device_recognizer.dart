import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Why the device's recognizer stopped without words.
enum DeviceRecognitionError { permission, network, nothingHeard, other }

/// The device's own speech recognizer (docs/08-speech.md §3.1, S2): the
/// learner's language is recognized here, the audio does not reach Dilbaz.
abstract interface class DeviceRecognizer {
  /// Whether the device can recognize [language] (`tr`); prepares the
  /// recognizer on first use.
  Future<bool> supports(String language);

  /// Listens until [stop]; [onWords] gets the words so far, [onError] why
  /// it stopped early.
  Future<void> listen({
    required String language,
    required Duration listenFor,
    required void Function(String words, {required bool done}) onWords,
    required void Function(DeviceRecognitionError error) onError,
  });

  Future<void> stop();

  Future<void> cancel();
}

/// [DeviceRecognizer] on `speech_to_text` (Android, iOS, macOS, Windows,
/// web).
class SpeechToTextRecognizer implements DeviceRecognizer {
  new([SpeechToText? plugin]) : _plugin = plugin ?? SpeechToText();

  final SpeechToText _plugin;
  void Function(DeviceRecognitionError error)? _onError;
  final _locales = <String, String?>{};

  /// A pause this long ends what is said.
  static const _pause = Duration(seconds: 4);

  @override
  Future<bool> supports(String language) async =>
      await _localeOf(language) != null;

  Future<String?> _localeOf(String language) async {
    if (_locales.containsKey(language)) return _locales[language];
    final ready = await _plugin.initialize(onError: _error);
    String? found;
    if (ready) {
      for (final locale in await _plugin.locales()) {
        final code = locale.localeId.toLowerCase().split(RegExp('[-_]')).first;
        if (code == language) {
          found = locale.localeId;
          break;
        }
      }
    }
    return _locales[language] = found;
  }

  void _error(SpeechRecognitionError error) {
    final kind = switch (error.errorMsg) {
      'error_insufficient_permissions' ||
      'error_permission' => DeviceRecognitionError.permission,
      'error_network' ||
      'error_network_timeout' ||
      'error_server' => DeviceRecognitionError.network,
      'error_no_match' ||
      'error_speech_timeout' => DeviceRecognitionError.nothingHeard,
      _ => DeviceRecognitionError.other,
    };
    _onError?.call(kind);
  }

  @override
  Future<void> listen({
    required String language,
    required Duration listenFor,
    required void Function(String words, {required bool done}) onWords,
    required void Function(DeviceRecognitionError error) onError,
  }) async {
    _onError = onError;
    await _plugin.listen(
      onResult: (result) =>
          onWords(result.recognizedWords, done: result.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: await _localeOf(language),
        listenFor: listenFor,
        pauseFor: _pause,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  @override
  Future<void> stop() => _plugin.stop();

  @override
  Future<void> cancel() => _plugin.cancel();
}
