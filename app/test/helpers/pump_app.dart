import 'package:dilbaz_app/app/app.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/share/share_providers.dart';
import 'package:dilbaz_app/data/share/shared_text_source.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/features/content/application/content_controller.dart';
import 'package:dilbaz_app/features/content/application/content_status.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';
import 'fake_profile_repository.dart';
import 'fake_speech.dart';
import 'placement_fixture.dart';

/// Content as the app has it once the course packs are imported.
const ContentStatus readyContent = ContentStatus.ready(
  words: 600,
  chunks: 120,
  sentences: 588,
);

/// Turkish UI strings, so tests never hard-code user-visible text.
final AppLocalizations trStrings = lookupAppLocalizations(const Locale('tr'));

/// Fakes for everything the app reaches outside itself, with the course
/// content already on the device. Unless [profiles] says otherwise, the
/// learner has finished the welcome flow; unless [assessments] and
/// [placements] say otherwise, no placement test is due.
List<Override> appOverrides({
  required FakeAuthRepository auth,
  FakeProfileRepository? profiles,
  FakeTeamRepository? teams,
  FakePermissionGateway? permissions,
  FakeAssessmentRepository? assessments,
  FakeBankRepository? placements,
  FakePackAudio? audio,
  FakeClipPlayer? player,
  FakeAnswerRecorder? recorder,
  FakeSpeechRepository? speech,
  FakeDictation? dictation,
  SharedTextSource? shared,
  List<Override> extra = const [],
}) => [
  authRepositoryProvider.overrideWithValue(auth),
  profileRepositoryProvider.overrideWithValue(
    profiles ?? FakeProfileRepository(onboarded: true),
  ),
  teamRepositoryProvider.overrideWithValue(teams ?? FakeTeamRepository()),
  permissionGatewayProvider.overrideWithValue(
    permissions ?? FakePermissionGateway(),
  ),
  contentControllerProvider.overrideWithBuild((ref, notifier) => readyContent),
  assessmentRepositoryProvider.overrideWithValue(
    assessments ?? FakeAssessmentRepository(open: false),
  ),
  placementBankRepositoryProvider.overrideWithValue(
    placements ?? FakeBankRepository(null),
  ),
  packAudioProvider.overrideWithValue(audio ?? FakePackAudio()),
  clipPlayerProvider.overrideWithValue(player ?? FakeClipPlayer()),
  answerRecorderProvider.overrideWithValue(recorder ?? FakeAnswerRecorder()),
  speechRepositoryProvider.overrideWithValue(speech ?? FakeSpeechRepository()),
  dictationProvider.overrideWithValue(dictation ?? FakeDictation()),
  sharedTextSourceProvider.overrideWithValue(
    shared ?? const NoSharedTextSource(),
  ),
  ...extra,
];

extension PumpApp on WidgetTester {
  /// Pumps the whole app with a fresh provider scope over [appOverrides].
  Future<FakeAuthRepository> pumpDilbazApp({
    bool signedIn = true,
    FakeAuthRepository? auth,
    FakeProfileRepository? profiles,
    FakeTeamRepository? teams,
    FakePermissionGateway? permissions,
    FakeAssessmentRepository? assessments,
    FakeBankRepository? placements,
    FakePackAudio? audio,
    FakeClipPlayer? player,
    FakeAnswerRecorder? recorder,
    FakeSpeechRepository? speech,
    FakeDictation? dictation,
    SharedTextSource? shared,
    List<Override> extra = const [],
  }) async {
    final fake = auth ?? FakeAuthRepository(signedIn: signedIn);
    await pumpWidget(
      ProviderScope(
        overrides: appOverrides(
          auth: fake,
          profiles: profiles,
          teams: teams,
          permissions: permissions,
          assessments: assessments,
          placements: placements,
          audio: audio,
          player: player,
          recorder: recorder,
          speech: speech,
          dictation: dictation,
          shared: shared,
          extra: extra,
        ),
        child: const DilbazApp(),
      ),
    );
    await pumpAndSettle();
    return fake;
  }
}
