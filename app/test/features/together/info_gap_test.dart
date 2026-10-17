import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/together/together_providers.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:dilbaz_app/features/sync/application/sync_controller.dart';
import 'package:dilbaz_app/features/together/application/info_gap_controller.dart';
import 'package:dilbaz_app/features/together/application/together_controller.dart'
    show pairTaskActivity, togetherActionsProvider, togetherProvider;
import 'package:dilbaz_app/features/together/application/together_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/fake_together.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';
import '../speaking/speaking_controller_test.dart' show marks;
import 'together_test.dart' show partnerId, self, team;

/// A session the partner started, with the learner in role b.
PairSession theirs(String taskRef, {PairState state = PairState.invited}) => (
  id: 'their-session',
  taskRef: taskRef,
  createdBy: partnerId,
  roles: {partnerId: 'a', self: 'b'},
  state: state,
  answers: const {},
  createdAt: cardNow,
);

void main() {
  late AppDatabase db;
  late FakeTogetherRepository server;
  late FakeTutorRepository tutor;
  late FakeSpeechRepository speech;
  late FakeAnswerRecorder recorder;
  late ProviderContainer container;
  var made = false;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
    server = FakeTogetherRepository(teamView: team);
    tutor = FakeTutorRepository()..annotated = marks;
    speech = FakeSpeechRepository(heard: 'is she sima dero');
    recorder = FakeAnswerRecorder();
    made = false;
  });

  tearDown(() async {
    if (made) container.dispose();
    await db.close();
  });

  void start() {
    container = ProviderContainer(
      overrides: [
        ...cardSessionOverrides(
          db: db,
          profiles: FakeProfileRepository(onboarded: true),
          tutor: tutor,
          speech: speech,
          recorder: recorder,
          audio: FakePackAudio(),
          player: FakeClipPlayer(),
        ),
        togetherRepositoryProvider.overrideWithValue(server),
        // The sync has its own tests; here the app stays on the device.
        syncControllerProvider.overrideWithBuild(
          (ref, notifier) => (lastSyncAt: null, changedAt: null, failure: null),
        ),
      ],
    )..listen(togetherProvider, (_, _) {});
    made = true;
  }

  Future<InfoGapState> gap(String id) async {
    final provider = infoGapControllerProvider(id);
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    return await container.read(provider.future);
  }

  InfoGapController controller(String id) =>
      container.read(infoGapControllerProvider(id).notifier);

  test('the tasks are offered; starting one waits for the partner', () async {
    start();
    final ready =
        await container.read(togetherProvider.future) as TogetherReady;
    expect(ready.gaps.map((t) => t.key), [gapChoose, gapDifferences]);
    expect(ready.gaps.first.b.options, hasLength(4));
    expect(ready.gaps.first.a.instruction, 'Sen anlat.');

    final id = await container
        .read(togetherActionsProvider.notifier)
        .startGap(ready.gaps.first);
    expect(server.calls, contains('start $gapChoose a'));
    expect(await gap(id!), isA<InfoGapWaiting>());
    await pumpEventQueue();
    final now = await container.read(togetherProvider.future) as TogetherReady;
    expect(now.gap?.session.id, id);
  });

  test('invited: join; choose, talk, answer; both in: solved, with the '
      "learner's own two corrections", () async {
    server.putSession(theirs(gapChoose));
    start();
    expect(await gap('their-session'), isA<InfoGapInvited>());
    await controller('their-session').join();
    await pumpEventQueue();
    var playing = await gap('their-session') as InfoGapPlaying;
    expect((playing.role, playing.chooses), ('b', true));
    expect(playing.mine.options.map((o) => o.id), ['p', 'q', 'r', 's']);

    final c = controller('their-session');
    // Nothing goes before a choice.
    await c.submit();
    expect(server.calls, isNot(contains('answer-session their-session')));
    await c.startSpeaking();
    await c.stopSpeaking();
    c.choose('q');
    await c.submit();
    playing =
        container.read(infoGapControllerProvider('their-session')).value!
            as InfoGapPlaying;
    expect((playing.said, playing.answered, playing.chosen), (1, true, 'q'));

    server.partnerAnswers('their-session', partnerId, 'done');
    await pumpEventQueue();
    await pumpEventQueue();
    final done = await gap('their-session') as InfoGapDone;
    expect(done.check.solved, isTrue);
    expect(done.feedback, isA<GapCorrections>());
    expect((done.feedback as GapCorrections).corrections, hasLength(2));
    expect(tutor.annotateAsked.single.goal, 'Find the friend.');
    expect(tutor.annotateAsked.single.words.map((w) => w.text), [
      'is',
      'she',
      'sima',
      'dero',
    ]);

    final attempt = (await db.select(db.attempts).get()).single;
    expect(attempt.activity, pairTaskActivity);
    expect(attempt.taskRef, gapChoose);
    expect(attempt.verdict, 'done');
    expect(attempt.response['answer'], 'q');
    expect(attempt.response['text'], 'is she sima dero');
    final session = (await db.select(db.sessions).get()).single;
    expect(session.strandMs.keys, ['output']);
    expect(session.planned, {'activity': pairTaskActivity, 'task': gapChoose});
    expect(session.done, {'found': 1, 'total': 1, 'with_partner': true});
  });

  test('differences: lines marked; nothing said, no feedback', () async {
    server.putSession(theirs(gapDifferences, state: PairState.active));
    start();
    final c = controller('their-session');
    await gap('their-session');
    c
      ..toggle(0)
      ..toggle(2)
      ..toggle(3)
      ..toggle(3);
    await c.submit();
    server.partnerAnswers('their-session', partnerId, [4]);
    await pumpEventQueue();
    await pumpEventQueue();
    final done = await gap('their-session') as InfoGapDone;
    expect((done.check.found, done.check.solved), (3, true));
    expect(done.feedback, const GapFeedback.nothingSaid());
    expect(tutor.annotateAsked, isEmpty);
    expect((await db.select(db.attempts).get()).single.response['answer'], [
      0,
      2,
    ]);
  });

  test('leaving cancels; a session that is gone says so', () async {
    server.putSession(theirs(gapChoose, state: PairState.active));
    start();
    await gap('their-session');
    await controller('their-session').cancel();
    await pumpEventQueue();
    expect(await gap('their-session'), const InfoGapState.cancelled());
    expect(await gap('none'), const InfoGapState.unavailable());
  });
}
