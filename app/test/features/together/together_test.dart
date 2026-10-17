import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/session_repository.dart';
import 'package:dilbaz_app/data/together/together_providers.dart';
import 'package:dilbaz_app/data/together/together_repository.dart';
import 'package:dilbaz_app/features/together/application/chat_card_controller.dart';
import 'package:dilbaz_app/features/together/application/together_controller.dart';
import 'package:dilbaz_app/features/together/application/together_view.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/fake_together.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';

const String self = FakeAuthRepository.id;
const partnerId = 'partner-1';
const TeamView team = (
  id: 'team-1',
  name: 'Biz',
  members: [(id: self, name: 'Berat'), (id: partnerId, name: 'Ada')],
);

PairInvite invited({
  String id = 'from-partner',
  String from = partnerId,
  String to = self,
  String taskRef = chatA,
  InviteState state = InviteState.sent,
  DateTime? at,
}) => (
  id: id,
  from: from,
  to: to,
  taskRef: taskRef,
  state: state,
  createdAt: at ?? cardNow,
);

void main() {
  late AppDatabase db;
  late FakeTogetherRepository server;
  late ProviderContainer container;
  var made = false;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
    server = FakeTogetherRepository(teamView: team);
    made = false;
  });

  tearDown(() async {
    if (made) container.dispose();
    await db.close();
  });

  ProviderContainer start() {
    container = ProviderContainer(
      overrides: [
        ...cardSessionOverrides(
          db: db,
          profiles: FakeProfileRepository(onboarded: true),
          tutor: FakeTutorRepository(),
          speech: FakeSpeechRepository(),
          recorder: FakeAnswerRecorder(),
          audio: FakePackAudio(),
          player: FakeClipPlayer(),
        ),
        togetherRepositoryProvider.overrideWithValue(server),
      ],
    )..listen(togetherProvider, (_, _) {});
    made = true;
    return container;
  }

  Future<TogetherView> view() => start().read(togetherProvider.future);

  group('the Together tab (F2-07)', () {
    test('no team, alone, or no server', () async {
      server.teamView = null;
      expect(await view(), const TogetherView.noTeam());
      container.dispose();
      server.teamView = (
        id: 'team-1',
        name: 'Biz',
        members: [(id: self, name: 'Berat')],
      );
      expect(await view(), const TogetherView.alone(teamName: 'Biz'));
      container.dispose();
      server.failure = TogetherFailure.network;
      expect(await view(), const TogetherView.offline());
    });

    test('the partner, whether here, and the chat cards in order', () async {
      final ready = await view() as TogetherReady;
      expect(ready.partner, (id: partnerId, name: 'Ada'));
      expect(ready.partnerHere, isFalse);
      expect(ready.cards.map((c) => c.key), [chatA, chatB]);
      expect(ready.cards.first.title, 'Yemek');
      expect(ready.cards.first.followUpMeanings, ['Kolu mu?', 'Sima mı?']);
      expect(server.calls, ['present team-1', 'week team-1']);

      server.setHere({partnerId});
      await pumpEventQueue();
      final here = await container.read(togetherProvider.future);
      expect((here as TogetherReady).partnerHere, isTrue);
    });

    test('a card talked about lately goes last', () async {
      await DriftSessionRepository(db).record(
        userId: self,
        courseId: FakeAssessmentRepository.zzCourse.id,
        deviceId: 'device-1',
        startedAt: cardNow.subtract(const Duration(days: 2)),
        endedAt: cardNow.subtract(const Duration(days: 2)),
        strands: {Strand.output: const Duration(minutes: 9)},
        planned: {'activity': chatActivity, 'task': chatA},
      );
      final ready = await view() as TogetherReady;
      expect(ready.cards.map((c) => c.key), [chatB, chatA]);
    });

    test("today's invitations: from the partner, own, agreed", () async {
      server
        ..receive(invited(at: cardNow.subtract(const Duration(days: 1))))
        ..receive(invited(id: 'today'));
      var ready = await view() as TogetherReady;
      expect(ready.incoming?.invite.id, 'today');
      expect(ready.incoming?.card.key, chatA);
      expect(ready.agreed, isNull);

      await container
          .read(togetherActionsProvider.notifier)
          .answer(ready.incoming!.invite, yes: true);
      await pumpEventQueue();
      ready = await container.read(togetherProvider.future) as TogetherReady;
      expect(ready.incoming, isNull);
      expect(ready.agreed?.key, chatA);
      expect(server.calls.last, 'answer today true');
    });

    test('inviting the partner; taking it back; a failure is told', () async {
      final ready = await view() as TogetherReady;
      final actions = container.read(togetherActionsProvider.notifier);
      await actions.invite(ready.cards.last);
      await pumpEventQueue();
      var now = await container.read(togetherProvider.future) as TogetherReady;
      expect(server.calls, contains('invite $partnerId $chatB'));
      expect(now.outgoing?.invite.state, InviteState.sent);
      expect(now.outgoing?.card.key, chatB);

      await actions.cancel(now.outgoing!.invite);
      await pumpEventQueue();
      now = await container.read(togetherProvider.future) as TogetherReady;
      expect(now.outgoing, isNull, reason: 'a cancelled one is not shown');

      server.failure = TogetherFailure.network;
      await actions.invite(ready.cards.first);
      expect(container.read(togetherActionsProvider), TogetherFailure.network);
      server.failure = null;
      await actions.invite(ready.cards.first);
      expect(container.read(togetherActionsProvider), isNull);
    });
  });

  group('the week together (F2-09)', () {
    test(
      "the shared goal, the partner's counts; today's cheer; sending one",
      () async {
        server
          ..teamWeek = (
            goalDays: 9,
            members: [
              (
                id: self,
                name: 'Berat',
                days: 2,
                minutes: 40,
                strands: {'language': 40},
                together: 1,
              ),
              (
                id: partnerId,
                name: 'Ada',
                days: 3,
                minutes: 55,
                strands: {'output': 20},
                together: 1,
              ),
            ],
          )
          ..cheered((
            id: 'old',
            from: partnerId,
            to: self,
            key: CheerKey.steady,
            createdAt: cardNow.subtract(const Duration(days: 1)),
          ))
          ..cheered((
            id: 'today',
            from: partnerId,
            to: self,
            key: CheerKey.speaking,
            createdAt: cardNow,
          ));
        final ready = await view() as TogetherReady;
        expect(ready.week?.goalDays, 9);
        expect(ready.week?.members.last.minutes, 55);
        expect(ready.cheer?.id, 'today');

        expect(
          await container
              .read(togetherActionsProvider.notifier)
              .cheer(CheerKey.together),
          isTrue,
        );
        expect(server.calls, contains('cheer $partnerId together'));
      },
    );

    test('without the week: the rest still shows', () async {
      server.teamWeek = null;
      final ready = await view() as TogetherReady;
      expect(ready.week, isNull);
      expect(ready.cards, isNotEmpty);
    });
  });

  group('a chat card (A14)', () {
    ChatCardControllerProvider card(String key) =>
        chatCardControllerProvider(key);

    test('open with its meanings; talked, then the time is the output '
        "strand's", () async {
      start();
      final provider = card(chatA);
      container.listen(provider, (_, _) {});
      final open = await container.read(provider.future) as ChatCardOpen;
      expect(open.card.question, 'Bada $chatA?');
      expect(open.meanings, isTrue, reason: 'A2 reads the meanings');

      final controller = container.read(provider.notifier);
      // Nothing to finish before they began.
      await controller.finish();
      expect(await db.select(db.sessions).get(), isEmpty);
      controller.start();
      await controller.finish();
      expect(
        container.read(provider).value,
        ChatCardState.done(card: open.card, spent: Duration.zero),
      );
      final session = (await db.select(db.sessions).get()).single;
      expect(session.strandMs.keys, ['output']);
      expect(session.planned, {'activity': chatActivity, 'task': chatA});
      expect(session.done, {'with_partner': true});
    });

    test('a card not in the packs', () async {
      start();
      expect(
        await container.read(card('zz.chat.none').future),
        const ChatCardState.unavailable(),
      );
    });
  });
}
