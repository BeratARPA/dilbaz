import 'package:just_audio/just_audio.dart';

/// Plays audio clips that are files on the device.
abstract interface class ClipPlayer {
  /// Plays the file at [path] to its end. False if it could not be played.
  Future<bool> play(String path);

  /// Stops what is playing.
  Future<void> stop();

  /// Frees the player.
  Future<void> dispose();
}

class JustAudioClipPlayer implements ClipPlayer {
  final _player = AudioPlayer();

  @override
  Future<bool> play(String path) async {
    try {
      await _player.setFilePath(path);
      // Completes when the clip has ended or was stopped.
      await _player.play();
      return true;
    } on PlayerException {
      return false;
    } on PlayerInterruptedException {
      return false;
    }
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
