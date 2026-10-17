import 'dart:convert';
import 'dart:typed_data';

import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'pron_check.freezed.dart';

/// A shadowed sentence and its recording for `tutor/pron_check`
/// (docs/07-ai-tutor.md §4.4, ADR-0011).
@freezed
abstract class PronCheckRequest with _$PronCheckRequest {
  const factory({
    required String l1,
    required String l2,
    required CefrLevel level,

    /// The sentence the learner heard and repeated.
    required String reference,

    /// The recording: 16 kHz WAV (`RecorderConfig.pronunciation`).
    required Uint8List wav,
  }) = _PronCheckRequest;

  const new _();

  /// The route's body.
  Map<String, Object?> toJson() => {
    'ctx': {'l1': l1, 'l2': l2, 'level': level.code, 'explain_in': 'l1'},
    'reference': reference,
    'audio': {'data': base64Encode(wav), 'mime_type': 'audio/wav'},
  };
}

/// What `tutor/pron_check` heard: problems the model was sure of, each a
/// word of the sentence and a pronunciation tag of the pair, or nothing
/// when the recording could not be judged. No score (I-04).
@freezed
abstract class HeardPronunciation with _$HeardPronunciation {
  const factory({
    /// The recording is silent, noise, or not the sentence.
    required bool uncertain,
    required List<PronIssue> issues,
    required String catalog,
    required String promptVersion,
    required String provider,
    required String model,
  }) = _HeardPronunciation;

  /// The route's answer; a [FormatException] when it is off the contract.
  factory read(Map<String, Object?> json) => switch (json) {
    {
      'uncertain': final bool uncertain,
      'issues': final List<Object?> issues,
      'catalog': final String catalog,
      'prompt_version': final String promptVersion,
      'provider': final String provider,
      'model': final String model,
    } =>
      HeardPronunciation(
        uncertain: uncertain,
        issues: [
          for (final issue in issues)
            switch (issue) {
              {
                'i': final int index,
                'word': final String word,
                'tag': final String tag,
                'heard': final String heard,
              } =>
                (index: index, word: word, tag: tag, heard: heard),
              _ => throw const FormatException('pron_check issue'),
            },
        ],
        catalog: catalog,
        promptVersion: promptVersion,
        provider: provider,
        model: model,
      ),
    _ => throw const FormatException('pron_check'),
  };

  const new _();

  /// What an attempt keeps of it (`attempts.llm`, docs/13).
  Map<String, Object?> toJson() => {
    'uncertain': uncertain,
    'issues': [
      for (final issue in issues)
        {
          'i': issue.index,
          'word': issue.word,
          'tag': issue.tag,
          'heard': issue.heard,
        },
    ],
    'catalog': catalog,
    'prompt_version': promptVersion,
    'provider': provider,
    'model': model,
  };
}
