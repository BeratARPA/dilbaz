import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:json_annotation/json_annotation.dart'
    show CheckedFromJsonException;

/// What `tutor/speaking_annotate` marked, and where the marks came from
/// (docs/07-ai-tutor.md §4.2): `recordings.annotation` keeps it whole.
final class AnnotatedSpeech {
  const new({
    required this.annotation,
    required this.catalog,
    required this.promptVersion,
    required this.provider,
    required this.model,
  });

  /// Reads the route's answer; throws [CheckedFromJsonException] when it
  /// is off the contract.
  factory fromJson(Map<String, Object?> json) {
    final annotation = SpeechAnnotation.fromJson(json);
    String text(String key) => switch (json[key]) {
      final String value => value,
      _ => throw CheckedFromJsonException(
        json,
        key,
        'AnnotatedSpeech',
        'not a string',
      ),
    };
    return AnnotatedSpeech(
      annotation: annotation,
      catalog: text('catalog'),
      promptVersion: text('prompt_version'),
      provider: text('provider'),
      model: text('model'),
    );
  }

  final SpeechAnnotation annotation;

  /// The pair pack whose tags the marks use.
  final String catalog;
  final String promptVersion;
  final String provider;
  final String model;

  /// As stored: the marks and their source.
  Map<String, Object?> toJson() => {
    ...annotation.toJson(),
    'catalog': catalog,
    'prompt_version': promptVersion,
    'provider': provider,
    'model': model,
  };
}
