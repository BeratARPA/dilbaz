import 'package:record/record.dart';

/// How speech is recorded (docs/08-speech.md §4): the one place where
/// encoders are chosen.
typedef RecordSpec = ({
  RecordConfig config,

  /// File name ending of a recording.
  String extension,

  /// Media type sent with the audio.
  String contentType,
});

abstract final class RecorderConfig {
  /// Speech for recognition: AAC-LC at 16 kHz, mono, about 32 kbps, in an
  /// MP4 (`.m4a`) container; the web records Opus in WebM instead.
  static RecordSpec speech({required bool web}) => web
      ? (
          config: const RecordConfig(
            encoder: AudioEncoder.opus,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 32000,
          ),
          extension: 'webm',
          contentType: 'audio/webm',
        )
      : (
          config: const RecordConfig(
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 32000,
          ),
          extension: 'm4a',
          contentType: 'audio/mp4',
        );

  /// Speech for pronunciation (S3, ADR-0011): uncompressed 16 kHz mono
  /// PCM16 in a WAV file, on every platform.
  static const RecordSpec pronunciation = (
    config: RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    ),
    extension: 'wav',
    contentType: 'audio/wav',
  );

  /// Longest answer of each kind, after which recording stops by itself.
  static const cardLimit = Duration(seconds: 12);
  static const shadowingLimit = Duration(seconds: 15);
  static const taskLimit = Duration(minutes: 2);
  static const fourThreeTwoLimit = Duration(minutes: 4);
}
