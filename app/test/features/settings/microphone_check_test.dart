import 'package:dilbaz_app/data/audio/answer_recorder.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/speech/speech_providers.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/features/settings/application/microphone_check_controller.dart';
import 'package:dilbaz_app/features/settings/application/microphone_check_state.dart';
import 'package:dilbaz_app/features/settings/presentation/microphone_check_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pump_app.dart';

void main() {
  late FakeProfileRepository profiles;
  late FakeAnswerRecorder recorder;
  late FakeSpeechRepository speech;
  late ProviderContainer container;

  setUp(() {
    profiles = FakeProfileRepository(onboarded: true);
    recorder = FakeAnswerRecorder();
    speech = FakeSpeechRepository();
  });

  Future<void> start() async {
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
        profileRepositoryProvider.overrideWithValue(profiles),
        answerRecorderProvider.overrideWithValue(recorder),
        speechRepositoryProvider.overrideWithValue(speech),
      ],
    )..listen(microphoneCheckControllerProvider, (_, _) {});
    await container.read(microphoneCheckControllerProvider.future);
  }

  tearDown(() => container.dispose());

  MicrophoneCheckController controller() =>
      container.read(microphoneCheckControllerProvider.notifier);
  MicrophoneCheckState? state() =>
      container.read(microphoneCheckControllerProvider).value;

  group('MicrophoneCheckController', () {
    test(
      'without the audio consent nothing is recorded (docs/14 §4)',
      () async {
        profiles.audioConsent = false;
        await start();

        expect(state(), const MicrophoneCheckState.noConsent());
        await controller().record();
        expect(recorder.starts, 0);
      },
    );

    test('records, then shows what was heard', () async {
      await start();

      await controller().record();
      expect(state(), const MicrophoneCheckState.recording());
      await controller().stop();

      final ready = state()! as MicrophoneCheckReady;
      expect(ready.heard!.text, 'he go to work');
      expect(speech.asked.single.contentType, 'audio/mp4');
    });

    test('a failure to record or to recognize is shown calmly', () async {
      await start();
      recorder.failure = RecordFailure.permission;
      await controller().record();
      expect(
        state(),
        const MicrophoneCheckState.ready(
          recordFailure: RecordFailure.permission,
        ),
      );

      recorder.failure = null;
      speech.failure = SpeechFailure.unavailable;
      await controller().record();
      await controller().stop();
      expect(
        state(),
        const MicrophoneCheckState.ready(failure: SpeechFailure.unavailable),
      );
    });

    test('nothing recorded is asked nothing', () async {
      await start();
      recorder.silent = true;
      await controller().record();
      await controller().stop();
      expect(state(), const MicrophoneCheckState.ready());
      expect(speech.asked, isEmpty);
    });
  });

  group('MicrophoneCheckScreen', () {
    testWidgets('is reached from the settings and writes what it heard', (
      tester,
    ) async {
      await tester.pumpDilbazApp(
        profiles: profiles,
        recorder: recorder,
        speech: speech,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(trStrings.tabProgress),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(trStrings.settingsTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(trStrings.microphoneCheckTitle));
      await tester.pumpAndSettle();

      expect(find.byType(MicrophoneCheckScreen), findsOneWidget);
      expect(find.text(trStrings.microphoneCheckBody), findsOneWidget);
      await tester.tap(find.text(trStrings.microphoneCheckRecord));
      await tester.pump();
      expect(find.text(trStrings.microphoneCheckStop), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.text(trStrings.microphoneCheckStop));
      await tester.pumpAndSettle();

      expect(find.text(trStrings.microphoneCheckHeard), findsOneWidget);
      expect(find.text('he go to work'), findsOneWidget);
    });

    testWidgets('an empty transcript and a failure read calmly', (
      tester,
    ) async {
      speech.heard = '';
      await tester.pumpDilbazApp(
        profiles: profiles,
        recorder: recorder,
        speech: speech,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(trStrings.tabProgress),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(trStrings.settingsTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(trStrings.microphoneCheckTitle));
      await tester.pumpAndSettle();

      await tester.tap(find.text(trStrings.microphoneCheckRecord));
      await tester.pump();
      await tester.tap(find.text(trStrings.microphoneCheckStop));
      await tester.pumpAndSettle();
      expect(find.text(trStrings.microphoneCheckNothing), findsOneWidget);

      speech.failure = SpeechFailure.quota;
      await tester.tap(find.text(trStrings.microphoneCheckRecord));
      await tester.pump();
      await tester.tap(find.text(trStrings.microphoneCheckStop));
      await tester.pumpAndSettle();
      expect(find.text(trStrings.speechFailureQuota), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });

  testWidgets('recording stops by itself at the length of a card answer', (
    tester,
  ) async {
    await tester.pumpDilbazApp(
      profiles: profiles,
      recorder: recorder,
      speech: speech,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(trStrings.tabProgress),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(trStrings.settingsTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(trStrings.microphoneCheckTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(trStrings.microphoneCheckRecord));
    await tester.pump();

    await tester.pump(const Duration(seconds: 11));
    expect(speech.asked, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(speech.asked, hasLength(1));
    expect(find.text('he go to work'), findsOneWidget);
  });

  test('every failure has its own text', () {
    expect({
      for (final f in SpeechFailure.values) speechFailureText(trStrings, f),
    }, hasLength(SpeechFailure.values.length));
    expect({
      for (final f in RecordFailure.values) recordFailureText(trStrings, f),
    }, hasLength(RecordFailure.values.length));
  });
}
