import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/attempt_draft.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_app/features/cards/application/card_session_controller.dart';
import 'package:dilbaz_app/features/cards/application/card_session_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';

/// Gives bada its own clips: a word with them gets a listening card.
Future<void> badaHeard(AppDatabase db) async {
  final row = await (db.select(
    db.contentItems,
  )..where((t) => t.key.equals(bada))).getSingle();
  await (db.update(db.contentItems)..where((t) => t.key.equals(bada))).write(
    ContentItemsCompanion(
      data: Value({
        ...row.data,
        'audio': [
          {'voice': 'v1', 'speed': 1.0, 'file': 'v1/w0001.mp3'},
          {'voice': 'v1', 'speed': 0.8, 'file': 'v1/w0001s.mp3'},
        ],
      }),
    ),
  );
}

/// Three more words with meanings: a listening card has four choices.
Future<void> moreMeanings(AppDatabase db) async {
  for (final (word, meaning) in [
    ('kolu', 'kolu demek'),
    ('dero', 'dero demek'),
    ('mi', 'mi demek'),
  ]) {
    await db
        .into(db.contentItems)
        .insert(
          item(
            'zz.ws.$word.n.1',
            'word_sense',
            packId: 'zz@1',
            text: word,
            lemmas: [word],
            level: 'C1',
          ),
        );
    await db
        .into(db.contentPairEntries)
        .insert(
          ContentPairEntriesCompanion.insert(
            kind: 'gloss',
            key: 'zz.ws.$word.n.1',
            packId: 'qq-zz@1',
            data: {'meaning': meaning},
          ),
        );
  }
}

/// The plan, read the way the Today screen reads it.
final _plan = FutureProvider<CardPlan?>(planCards);

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakeTutorRepository tutor;
  late FakeSpeechRepository speech;
  late FakeAnswerRecorder recorder;
  late FakePackAudio audio;
  late FakeClipPlayer player;
  late ProviderContainer container;
  late CardSessionControllerProvider session;
  var made = false;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
    profiles = FakeProfileRepository(onboarded: true);
    tutor = FakeTutorRepository();
    speech = FakeSpeechRepository(heard: 'bada kolu');
    recorder = FakeAnswerRecorder();
    audio = FakePackAudio();
    player = FakeClipPlayer();
    made = false;
  });

  tearDown(() async {
    if (made) container.dispose();
    await db.close();
  });

  CardSessionController controller() => container.read(session.notifier);
  CardSessionState? current() => container.read(session).value;

  Future<CardSessionState> start() async {
    session = cardSessionControllerProvider();
    container = ProviderContainer(
      overrides: cardSessionOverrides(
        db: db,
        profiles: profiles,
        tutor: tutor,
        speech: speech,
        recorder: recorder,
        audio: audio,
        player: player,
      ),
    )..listen(session, (_, _) {});
    made = true;
    return await container.read(session.future);
  }

  Future<List<AttemptRow>> attempts() => (db.select(
    db.attempts,
  )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get();

  /// A card of bada in [mode], made [daysAgo] and due now.
  Future<StoredCard> due(CardMode mode, {int daysAgo = 3}) =>
      DriftCardRepository(
        db,
        now: () => cardNow.subtract(Duration(days: daysAgo)),
      ).introduce(
        userId: FakeAuthRepository.id,
        courseId: FakeAssessmentRepository.zzCourse.id,
        itemRef: bada,
        mode: mode,
      );

  Future<Set<String>> modesOfBada() async => {
    for (final card in await db.select(db.cards).get())
      if (card.itemRef == bada) card.mode,
  };

  group('the listening card (A03)', () {
    test('a word introduced at A0–B1 gets one with its first card', () async {
      await badaHeard(db);
      await start();
      controller().begin();
      speech.heard = 'bada kolu';
      await controller().startSpeaking();
      await controller().stopSpeaking();
      await controller().next();
      expect(await modesOfBada(), {'speak', 'recognize_audio'});
      // A word without a clip of its own gets none.
      expect(
        (await db.select(db.cards).get()).where((c) => c.itemRef == sima),
        isEmpty,
      );
    });

    test('hear it, then choose; the choice rates it (Good)', () async {
      await badaHeard(db);
      await moreMeanings(db);
      final card = await due(CardMode.recognizeAudio);
      final view = (await start() as CardSessionRecognize).view;
      expect(view.choices, hasLength(4));
      expect(view.choices, contains('bada demek'));
      // sima is at bada's level: the nearest other meaning comes first.
      expect(view.choices, contains('sima demek'));
      // The clip plays by itself; the choices open once it was heard.
      await pumpEventQueue();
      expect(audio.fetched.first, 'zz/v1/w0001.mp3');
      var now = (current()! as CardSessionRecognize).view;
      expect(now.heard, isTrue);
      final right = now.choices.indexOf('bada demek');
      controller().choose(right);
      now = (current()! as CardSessionRecognize).view;
      expect((now.chosen, now.right, now.headword), (right, right, 'bada'));
      // One choice: it cannot be changed.
      controller().choose((right + 1) % 4);
      expect((current()! as CardSessionRecognize).view.chosen, right);
      await controller().next();

      final attempt = (await attempts()).single;
      expect(attempt.activity, 'card.recognize_audio');
      expect(attempt.cardId, card.id);
      expect(attempt.verdict, 'correct');
      expect(attempt.rating, ReviewRating.good.code);
      expect(attempt.response, {
        'choice': right,
        'text': 'bada demek',
        'source': 'choice',
      });
      // Recognition is no production evidence (I-05).
      final evidence = await DriftCardRepository(db)
          .evidence(FakeAssessmentRepository.zzCourse.id, itemRef: bada);
      expect(evidence[bada]!.productionLevel(now: cardNow), ItemLevel.unseen);
    });

    test(
      'nothing to choose before hearing; another meaning is Again',
      () async {
        await badaHeard(db);
        await moreMeanings(db);
        profiles.silentMode = true;
        await due(CardMode.recognizeAudio);
        await start();
        // Silent mode: nothing plays by itself, and nothing can be chosen.
        await pumpEventQueue();
        expect(audio.fetched, isEmpty);
        controller().choose(0);
        expect((current()! as CardSessionRecognize).view.chosen, isNull);
        await controller().play();
        final view = (current()! as CardSessionRecognize).view;
        final wrong = view.choices.indexWhere((c) => c != 'bada demek');
        controller().choose(wrong);
        expect((current()! as CardSessionRecognize).view.right, isNot(wrong));
        await controller().leave();
        final attempt = (await attempts()).single;
        expect(attempt.verdict, 'wrong');
        expect(attempt.rating, ReviewRating.again.code);
        expect(await db.select(db.sessions).get(), hasLength(1));
      },
    );

    test('without enough meanings or its clip it waits', () async {
      await badaHeard(db);
      await due(CardMode.recognizeAudio);
      final state = await start();
      expect(state, isNot(isA<CardSessionRecognize>()));
    });
  });

  group('the cloze card (A04)', () {
    test('the sentence with its gap; the answer fills it', () async {
      final card = await due(CardMode.cloze);
      final view = (await start() as CardSessionCard).view;
      expect(view.cloze, (before: '', after: ' kolu.', hint: 'bada demek'));
      await controller().submit('bada');
      final ended = (current()! as CardSessionCard).view.phase as CardEnded;
      expect(ended.outcome, isA<Recalled>());
      await controller().next();
      final attempt = (await attempts()).single;
      expect(attempt.activity, 'card.cloze');
      expect(attempt.cardId, card.id);
      expect(attempt.response['text'], 'bada kolu.');
      expect(attempt.response['gap'], 'bada');
      expect(attempt.prompt['cloze'], {
        'before': '',
        'after': ' kolu.',
        'hint': 'bada demek',
      });
      expect(tutor.asked, isEmpty);
    });

    test('a wrong gap goes to the LLM as the whole sentence', () async {
      await due(CardMode.cloze);
      await start();
      speech.heard = 'dero';
      await controller().startSpeaking();
      await controller().stopSpeaking();
      expect(tutor.asked.single.answer, 'dero kolu.');
      expect((current()! as CardSessionCard).view.last?.text, 'dero kolu.');
    });

    test('a word recalled for a week and more gets one', () async {
      final card = await due(CardMode.speak, daysAgo: 20);
      await DriftCardRepository(db).recordReview(
        userId: FakeAuthRepository.id,
        courseId: FakeAssessmentRepository.zzCourse.id,
        deviceId: 'device-1',
        card: card,
        attempts: [
          AttemptDraft(
            activity: cardActivity(CardMode.speak),
            prompt: const {},
            response: const {'text': 'bada kolu', 'source': 'asr'},
            createdAtClient: cardNow.subtract(const Duration(days: 12)),
            verdict: 'correct',
            targetOk: true,
          ),
        ],
        rating: ReviewRating.good,
        after: CardMemory(
          fsrsCardId: 1,
          state: MemoryState.review,
          due: cardNow,
          stability: 12,
          difficulty: 5,
          lastReview: cardNow.subtract(const Duration(days: 12)),
          reps: 1,
        ),
      );
      expect(await modesOfBada(), {'speak'});
      await start();
      speech.heard = 'bada kolu';
      await controller().startSpeaking();
      await controller().stopSpeaking();
      await controller().next();
      expect(await modesOfBada(), {'speak', 'cloze'});
      // A cloze card made today is no new item of today.
      expect((await container.read(_plan.future))!.newToday, 0);
    });

    test('not yet recalled: no cloze card', () async {
      await start();
      controller().begin();
      await controller().startSpeaking();
      await controller().stopSpeaking();
      await controller().next();
      expect(await modesOfBada(), {'speak'});
    });
  });
}
