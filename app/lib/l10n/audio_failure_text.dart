import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/l10n/gen/app_localizations.dart';

/// The calm text for a speech [failure].
String speechFailureText(AppLocalizations l10n, SpeechFailure failure) =>
    switch (failure) {
      SpeechFailure.network => l10n.speechFailureNetwork,
      SpeechFailure.unavailable => l10n.speechFailureUnavailable,
      SpeechFailure.quota => l10n.speechFailureQuota,
      SpeechFailure.busy => l10n.speechFailureBusy,
      SpeechFailure.badAudio => l10n.speechFailureBadAudio,
      SpeechFailure.unknown => l10n.speechFailureUnknown,
    };

/// The calm text for a recording [failure].
String recordFailureText(AppLocalizations l10n, RecordFailure failure) =>
    switch (failure) {
      RecordFailure.permission => l10n.recordFailurePermission,
      RecordFailure.unsupported => l10n.recordFailureUnsupported,
      RecordFailure.device => l10n.recordFailureDevice,
    };
