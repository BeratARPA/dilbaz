import 'package:dilbaz_app/data/gap/gap_entry.dart';
import 'package:dilbaz_app/l10n/l10n.dart';

/// Where a capture came up, as a chip says it.
String gapContextText(AppLocalizations l10n, GapContext context) =>
    switch (context) {
      GapContext.liveClass => l10n.gapContextLiveClass,
      GapContext.daily => l10n.gapContextDaily,
      GapContext.pair => l10n.gapContextPair,
      GapContext.speakingTask => l10n.gapContextSpeakingTask,
      GapContext.media => l10n.gapContextMedia,
    };
