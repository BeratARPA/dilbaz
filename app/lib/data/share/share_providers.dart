import 'package:dilbaz_app/data/share/shared_text_source.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'share_providers.g.dart';

/// The share menu target of this platform; tests override it.
@Riverpod(keepAlive: true)
SharedTextSource sharedTextSource(Ref ref) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? ShareHandlerTextSource()
    : const NoSharedTextSource();

/// Every text shared to the app: what it was opened with, then the rest.
@Riverpod(keepAlive: true)
Stream<String> sharedTexts(Ref ref) async* {
  final source = ref.watch(sharedTextSourceProvider);
  final first = (await source.initial())?.trim();
  if (first != null && first.isNotEmpty) {
    await source.clear();
    yield first;
  }
  await for (final text in source.texts()) {
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) yield trimmed;
  }
}

/// A shared text that waits for the home screen: before sign-in and the
/// welcome flow there is nowhere to capture it.
@Riverpod(keepAlive: true)
class PendingShare extends _$PendingShare {
  @override
  String? build() {
    ref.listen(sharedTextsProvider, (_, next) {
      if (next case AsyncData(:final value)) state = value;
    });
    return null;
  }

  /// The waiting text, handed over once.
  String? take() {
    final text = state;
    state = null;
    return text;
  }
}
