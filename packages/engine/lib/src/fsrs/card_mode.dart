import 'package:dilbaz_engine/src/fsrs/mode_group.dart';

/// How a card is practised; a card is one learner × item × mode
/// (docs/04-learner-model.md §2).
enum CardMode {
  /// Say the target-language form of a native-language prompt (A01).
  speak('speak', ModeGroup.production),

  /// Type it; the default in silent mode (A02).
  type('type', ModeGroup.production),

  /// Fill a gap in a target-language sentence (A04).
  cloze('cloze', ModeGroup.production),

  /// Produce one side of a contrast (A08).
  contrast('contrast', ModeGroup.production),

  /// Understand a word or chunk by ear (A03); never production (I-05).
  recognizeAudio('recognize_audio', ModeGroup.receptive),

  /// Write down a heard sentence (A05).
  dictation('dictation', ModeGroup.dictation);

  new(this.code, this.group);

  /// Code stored in `cards.mode`.
  final String code;

  /// Group whose FSRS weights schedule this mode.
  final ModeGroup group;
}
