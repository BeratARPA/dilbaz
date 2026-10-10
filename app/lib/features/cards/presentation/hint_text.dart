import 'package:dilbaz_app/features/cards/application/card_session_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';

/// The words of a [hint]: the LLM's own, or the template's (docs/03 §0.5).
/// A template tells the kind and the place of a difference and nothing of
/// the answer (I-02).
String hintText(AppLocalizations l10n, Hint hint) => switch (hint) {
  WrittenHint(:final text) => text,
  KindHint(:final kind) => switch (kind) {
    HintKind.missingWord => l10n.hintMissingWord,
    HintKind.extraWord => l10n.hintExtraWord,
    HintKind.wrongForm => l10n.hintWrongForm,
    HintKind.wordOrder => l10n.hintWordOrder,
    HintKind.meaning => l10n.hintMeaning,
  },
  PlaceHint(:final place) => switch (place.relation) {
    HintRelation.at => l10n.hintPlaceAt(place.word),
    HintRelation.before => l10n.hintPlaceBefore(place.word),
    HintRelation.after => l10n.hintPlaceAfter(place.word),
  },
};
