import 'package:dilbaz_app/features/placement/application/placement_state.dart';
import 'package:dilbaz_app/l10n/l10n.dart';

/// A part with the time it takes, for the overview.
String partLength(AppLocalizations l10n, PlacementPart part) => switch (part) {
  PlacementPart.words => l10n.placementPartWords,
  PlacementPart.grammar => l10n.placementPartGrammar,
  PlacementPart.dictation => l10n.placementPartDictation,
};

/// The title of a part.
String partTitle(AppLocalizations l10n, PlacementPart part) => switch (part) {
  PlacementPart.words => l10n.placementWordsTitle,
  PlacementPart.grammar => l10n.placementGrammarTitle,
  PlacementPart.dictation => l10n.placementDictationTitle,
};

/// What a part asks the learner to do.
String partIntro(AppLocalizations l10n, PlacementPart part) => switch (part) {
  PlacementPart.words => l10n.placementWordsIntro,
  PlacementPart.grammar => l10n.placementGrammarIntro,
  PlacementPart.dictation => l10n.placementDictationIntro,
};
