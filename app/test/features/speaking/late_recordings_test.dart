import 'dart:typed_data';

import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/notifications/notification_gateway.dart';
import 'package:dilbaz_app/data/notifications/notification_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/tasks/recording_repository.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/speaking/application/late_recordings.dart';
import 'package:dilbaz_app/l10n/l10n.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import 'speaking_controller_test.dart' show marks, said;

/// Notes shown at once, counted; the system allows them unless told.
final class _Notes implements NotificationGateway {
  bool permitted = true;
  final shown = <String>[];

  @override
  Future<bool> allowed() async => permitted;

  @override
  Future<void> setAhead(
    NotificationChannel channel,
    List<ScheduledNote> notes,
  ) async {}

  @override
  Future<void> show(NotificationChannel channel, String text) async =>
      shown.add(text);
}

const InvitationSettings _wanted = (
  wanted: true,
  anchor: 'morning_coffee',
  time: (hour: 8, minute: 30),
  quiet: null,
);

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakeTutorRepository tutor;
  late FakeSpeechRepository speech;
  late _Notes notes;
  late ProviderContainer container;
  final ready = lookupAppLocalizations(const Locale('tr')).notifyFeedbackReady;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
    profiles = FakeProfileRepository(onboarded: true)..invitation = _wanted;
    tutor = FakeTutorRepository()..annotated = marks;
    speech = FakeSpeechRepository(heard: said);
    notes = _Notes();
    container = ProviderContainer(
      overrides: [
        ...cardSessionOverrides(
          db: db,
          profiles: profiles,
          tutor: tutor,
          speech: speech,
          recorder: FakeAnswerRecorder(),
          audio: FakePackAudio(),
          player: FakeClipPlayer(),
        ),
        notificationGatewayProvider.overrideWithValue(notes),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  LateRecordings late() => container.read(lateRecordingsProvider);
  Future<int> run() => late().run(FakeAuthRepository.id);
  Future<RecordingRow> row(String id) async =>
      (await DriftRecordingRepository(db).recording(id))!;

  /// A recording of [taskRef] made [ago], its audio on this device unless
  /// [here] is false; nothing written down yet.
  Future<void> kept(
    String id, {
    String taskRef = homeTask,
    Duration ago = const Duration(minutes: 10),
    bool here = true,
    bool assessment = false,
  }) async {
    final path = '/recordings/$id.m4a';
    if (here) {
      (container.read(
        recordingStoreProvider,
      ) as FakeRecordingStore).files[path] = Uint8List(
        64,
      );
    }
    await DriftRecordingRepository(db, now: () => cardNow.subtract(ago)).create(
      id: id,
      userId: FakeAuthRepository.id,
      courseId: FakeAssessmentRepository.zzCourse.id,
      taskRef: taskRef,
      audioPath: path,
      duration: const Duration(seconds: 30),
      isAssessment: assessment,
    );
  }

  test('a recording made offline is written down, measured and marked; its '
      'feedback waits and is told once', () async {
    await kept('rec-1');

    expect(await run(), 2);

    final done = await row('rec-1');
    expect(done.timedWords, hasLength(6));
    expect(done.metrics, isNotNull);
    expect(done.annotated, isNotNull);
    expect(tutor.annotateAsked.single.assessment, isFalse);
    expect(notes.shown, [ready]);
    final waiting = await DriftRecordingRepository(db).readyFeedback(
      FakeAssessmentRepository.zzCourse.id,
      cardNow.subtract(const Duration(days: 7)),
    );
    expect(waiting.map((r) => r.id), ['rec-1']);
    // Nothing waits any more.
    expect(await run(), 0);
    expect(notes.shown, hasLength(1));
  });

  test('a young recording is left to its own screen; audio elsewhere to '
      'its own device', () async {
    await kept('young', ago: const Duration(minutes: 1));
    await kept('elsewhere', here: false);
    expect(await run(), 0);
    expect(speech.asked, isEmpty);
  });

  test('out of reach, it stops and tries again after the next sync', () async {
    await kept('rec-1');
    speech.failure = SpeechFailure.network;
    expect(await run(), 1);
    expect((await row('rec-1')).asr, isNull);
    expect(tutor.annotateAsked, isEmpty);

    speech.failure = null;
    tutor
      ..annotated = null
      ..annotateFailure = TutorFailure.network;
    expect(await run(), 2);
    final written = await row('rec-1');
    expect(written.asr, isNotNull);
    // Measured without marks; the marks wait.
    expect(written.metrics, isNotNull);
    expect(written.annotation, isNull);
    expect(notes.shown, isEmpty);
  });

  test('a recording the tutor refuses is not asked again', () async {
    await kept('rec-1');
    tutor
      ..annotated = null
      ..annotateFailure = TutorFailure.refused;
    await run();
    expect((await row('rec-1')).annotation, {'failed': 'refused'});
    expect(await run(), 0);
  });

  test('nothing heard in it: nothing to mark', () async {
    await kept('rec-1');
    speech.heard = '';
    expect(await run(), 1);
    expect(tutor.annotateAsked, isEmpty);
    expect(await run(), 0);
  });

  test('a test recording is marked as a test, and tells nothing', () async {
    await kept('rec-1', taskRef: anchorTask, assessment: true);
    await run();
    expect(tutor.annotateAsked.single.assessment, isTrue);
    expect(notes.shown, isEmpty);
  });

  test('without the audio consent nothing goes anywhere (I-18)', () async {
    await kept('rec-1');
    profiles.audioConsent = false;
    expect(await run(), 0);
    expect(speech.asked, isEmpty);
  });

  test('the notice only where the learner takes them, outside quiet hours '
      '(docs/09 §6)', () async {
    await kept('rec-1');
    profiles.invitation = (
      wanted: false,
      anchor: _wanted.anchor,
      time: _wanted.time,
      quiet: null,
    );
    await run();
    expect(notes.shown, isEmpty);

    await kept('rec-2');
    final local = cardNow.toLocal();
    profiles.invitation = (
      wanted: true,
      anchor: _wanted.anchor,
      time: _wanted.time,
      quiet: QuietHours(
        from: (hour: local.hour, minute: 0),
        to: (hour: (local.hour + 1) % 24, minute: 0),
      ),
    );
    await run();
    expect(notes.shown, isEmpty);

    await kept('rec-3');
    profiles.invitation = _wanted;
    notes.permitted = false;
    await run();
    expect(notes.shown, isEmpty);
  });

  test('a run makes a few calls at most: the quotas are shared', () async {
    for (var i = 1; i <= 4; i++) {
      await kept('rec-$i');
    }
    expect(await run(), LateRecordings.perRun);
    expect(speech.asked, hasLength(2));
  });
}
