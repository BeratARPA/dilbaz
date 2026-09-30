import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why speech could not be recognized; each maps to a calm text, and a
/// spoken card falls back to a typed one (docs/08-speech.md §5.3).
enum SpeechFailure {
  /// No connection.
  network,

  /// The recognizer is not set up, or its provider refused the server.
  unavailable,

  /// The provider's free quota or credit is spent.
  quota,

  /// The provider is busy for now.
  busy,

  /// The audio could not be read.
  badAudio,

  unknown,
}

/// Recognizes spoken answers through the `speech` function
/// (docs/08-speech.md §5.1).
abstract interface class SpeechRepository {
  /// What was said in [audio], in the language [lang].
  Future<Result<Transcript, SpeechFailure>> transcribe(
    RecordedAudio audio, {
    String lang = 'en',
  });
}

class SupabaseSpeechRepository implements SpeechRepository {
  const new(this._client);

  final SupabaseClient _client;

  static const _route = 'speech/transcribe';

  @override
  Future<Result<Transcript, SpeechFailure>> transcribe(
    RecordedAudio audio, {
    String lang = 'en',
  }) async {
    try {
      final response = await _client.functions.invoke(
        _route,
        body: audio.bytes,
        headers: {'Content-Type': audio.contentType},
        queryParameters: {'lang': lang},
      );
      return Ok(Transcript.fromJson(response.data as Map<String, Object?>));
    } on FunctionsFetchException {
      return const Err(SpeechFailure.network);
    } on FunctionException catch (error) {
      return Err(speechFailure(error.details));
    }
  }
}

/// Maps the stable error code of the `speech` function.
SpeechFailure speechFailure(Object? details) => switch (details) {
  {'error': {'code': final String code}} => switch (code) {
    'stt_unavailable' || 'unsupported_language' => SpeechFailure.unavailable,
    'stt_quota' => SpeechFailure.quota,
    'stt_busy' => SpeechFailure.busy,
    'bad_audio' ||
    'empty_audio' ||
    'unsupported_audio' ||
    'audio_too_large' => SpeechFailure.badAudio,
    // The provider did not answer the server: a passing trouble.
    'stt_failed' => SpeechFailure.busy,
    _ => SpeechFailure.unknown,
  },
  _ => SpeechFailure.unknown,
};
