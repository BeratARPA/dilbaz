import 'package:share_handler/share_handler.dart';

/// Text shared to the app from another one (Android share menu, A19).
abstract interface class SharedTextSource {
  /// What the app was opened with, if anything.
  Future<String?> initial();

  /// What is shared while the app runs.
  Stream<String> texts();

  /// Forgets what the app was opened with, once it is taken.
  Future<void> clear();
}

/// [SharedTextSource] on `share_handler` (Android, iOS).
class ShareHandlerTextSource implements SharedTextSource {
  ShareHandlerPlatform get _platform => ShareHandlerPlatform.instance;

  @override
  Future<String?> initial() async =>
      (await _platform.getInitialSharedMedia())?.content;

  @override
  Stream<String> texts() => _platform.sharedMediaStream
      .map((media) => media.content)
      .where((text) => text != null)
      .cast<String>();

  @override
  Future<void> clear() => _platform.resetInitialSharedMedia();
}

/// Platforms without a share menu target.
class NoSharedTextSource implements SharedTextSource {
  const new();

  @override
  Future<String?> initial() async => null;

  @override
  Stream<String> texts() => const Stream.empty();

  @override
  Future<void> clear() async {}
}
