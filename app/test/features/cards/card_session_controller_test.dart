import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_app/data/speech/speech_repository.dart';
import 'package:dilbaz_app/data/tutor/llm_answer_check.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
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

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakeTutorRepository tutor;
  late FakeSpeechRepository speech;
  late FakeAnswerRecorder recorder;
  late FakePackAudio audio;
  late FakeClipPlayer player;
  late ProviderContainer container;
  var containerMade = false;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
    profiles = FakeProfileRepository(onboarded: true);
    tutor = FakeTutorRepository();
    speech = FakeSpeechRepository(heard: 'bada kolu');
    recorder = FakeAnswerRecorder();
    audio = FakePackAudio();
    player = FakeClipPlayer();
    containerMade = false;
  });

  tearDown(() async {
    if (containerMade) container.dispose();
    await db.close();
  });

  CardSessionController controller() =>
      container.read(cardSessionControllerProvider.notifier);

  CardSessionState? current() =>
      container.read(cardSessionControllerProvider).value;

  CardView card() => (current()! as CardSessionCard).view;

  Future<CardSessionState> start() async {
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
    )..listen(cardSessionControllerProvider, (_, _) {});
    containerMade = true;
    return await container.read(cardSessionControllerProvider.future);
  }

  /// Opens the first new item's card.
  Future<void> startCard() async {
    await start();
    controller().begin();
  }

  Future<void> say(String heard) async {
    speech.heard = heard;
    await controller().startSpeaking();
    await controller().stopSpeaking();
  }

  Future<List<AttemptRow>> attempts() => (db.select(
    db.attempts,
  )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get();

  Future<void> finishCard() async {
    await controller().next();
  }

  group('a new item (A00 → A01)', () {
    test('is introduced with its sentence, meaning and notes', () async {
      final state = await start();
      final view = (state as CardSessionIntroduction).view;
      expect(view.number, 1);
      expect(view.total, 3);
      expect(view.headword, 'bada');
      expect(view.meaning, 'bada demek');
      expect(view.sentence, 'Bada kolu.');
      expect(view.sentenceMeaning, 'Bada kolu diye sor.');
      expect(view.usageNote, 'hep böyle');
      expect(view.hasClip, isTrue);
      // The sentence plays by itself, slowly at A0–A1 only (A2 here).
      await pumpEventQueue();
      expect(audio.fetched, ['zz/v1/0001.mp3']);
      expect(player.played, ['/clips/zz/v1/0001.mp3']);
    });

    test('then asked once: a spoken recall is Good, never Easy', () async {
      await startCard();
      expect(card().prompt, 'Bada kolu diye sor.');
      expect(card().contextNote, 'dosta');
      expect(card().input, AnswerInput.speak);
      await say('bada kolu');

      final phase = card().phase as CardEnded;
      expect(
        phase.outcome,
        isA<Recalled>().having((o) => o.firstTry, 'firstTry', isTrue),
      );
      expect(phase.sentence, 'Bada kolu.');
      expect(phase.correction, isNull);
      // A listed answer needs no LLM (docs/03 §0.5 step 2).
      expect(tutor.asked, isEmpty);

      await finishCard();
      final stored = await attempts();
      expect(stored, hasLength(1));
      final attempt = stored.single;
      expect(attempt.itemRef, bada);
      expect(attempt.activity, 'card.produce_speak');
      expect(attempt.verdict, 'correct');
      expect(attempt.targetOk, isTrue);
      expect(attempt.rating, ReviewRating.good.code);
      expect(attempt.response['source'], 'asr');
      expect(attempt.response['transcript'], 'bada kolu');
      expect(attempt.prompt['carrier'], badaSentence);
      expect(attempt.llm, isNull);
      expect(attempt.cardStateAfter, isNotNull);
      final cards = await db.select(db.cards).get();
      expect(cards.single.itemRef, bada);
      expect(cards.single.mode, 'speak');
      final outbox = await db.select(db.outbox).get();
      expect(outbox.map((e) => e.targetTable), ['cards', 'attempts', 'cards']);
      // The next new item follows.
      expect(current(), isA<CardSessionIntroduction>());
    });
  });

  group('the answer is shown only after a try (I-01)', () {
    test('no hint and no answer before the first answer', () async {
      await startCard();
      expect(card().hints, isEmpty);
      expect(card().canHint, isFalse);
      expect(card().canReveal, isFalse);
      controller()
        ..reveal()
        ..nextHint();
      expect(card().phase, isA<CardAsking>());
      expect(await attempts(), isEmpty);
    });

    test('nothing is sent to the LLM without an answer (I-11)', () async {
      await startCard();
      controller().switchInput();
      await controller().submit('   ');
      expect(tutor.asked, isEmpty);
      expect(card().phase, isA<CardAsking>());
    });
  });

  group('the hint ladder (I-02)', () {
    test('a miss opens H1, the next H2; the answer ends it as Again', () async {
      tutor.answers.addAll([
        llmCheck(
          Verdict.wrong,
          tags: const ['zz.form'],
          spans: const [ErrorSpan(start: 5, end: 9, tag: 'zz.form')],
          ladder: const LlmLadder(
            h1: 'Biçim yanlış.',
            h2: '',
            h3: 'Kural.',
            h4: 'Bada kolu.',
          ),
        ),
        llmCheck(
          Verdict.wrong,
          ladder: const LlmLadder(
            h1: 'Yine biçim.',
            h2: 'İkinci kelimede.',
            h3: 'Kural.',
            h4: 'Bada kolu!',
          ),
        ),
      ]);
      await startCard();
      controller().switchInput();
      await controller().submit('Kolu.');

      var view = card();
      expect(view.phase, isA<CardAsking>());
      expect(view.last!.feedback, AnswerFeedback.tryAgain);
      expect(view.last!.spans, const [
        ErrorSpan(start: 5, end: 9, tag: 'zz.form'),
      ]);
      expect(view.hints, const [Hint.written('Biçim yanlış.')]);
      // H2 was blanked by the leak check: the template tells the place.
      expect(view.canHint, isTrue);
      controller().nextHint();
      view = card();
      expect(view.hints, hasLength(2));
      expect(view.hints[1], isA<PlaceHint>());

      final request = tutor.asked.single;
      expect(request.level, CefrLevel.a2);
      expect(request.explainInL1, isTrue);
      expect(request.variants, ['Kolu bada.']);
      expect(request.alternatives, ['Sima kolu.']);
      expect(request.targetSpan, 'bada');
      expect(request.attemptNo, 1);
      expect(request.typed, isTrue);

      await controller().submit('Bada kolo!');
      expect(tutor.asked.last.attemptNo, 2);
      expect(tutor.asked.last.previousResponses, ['Kolu.']);
      view = card();
      // H2 was open: the second miss opens H3.
      expect(view.hints, const [
        Hint.written('Yine biçim.'),
        Hint.written('İkinci kelimede.'),
        Hint.written('Kural.'),
      ]);
      expect(view.canHint, isFalse);
      expect(view.canReveal, isTrue);

      controller().reveal();
      final phase = card().phase as CardEnded;
      expect(phase.outcome, isA<NotRecalled>());
      expect(phase.correction, 'Bada kolu!');

      await finishCard();
      final stored = await attempts();
      expect(stored.map((a) => a.verdict), ['wrong', 'wrong']);
      expect(stored.first.errorTags, ['zz.form']);
      expect(stored.first.parentAttemptId, isNull);
      expect(stored.last.parentAttemptId, stored.first.id);
      expect(stored.last.rating, ReviewRating.again.code);
      // The answer was opened on request: H4 on the rated attempt.
      expect(stored.last.hintMaxLevel, CardReview.answerLevel);
      expect(stored.last.llm, containsPair('provider', 'fake'));
      expect(stored.first.activity, 'card.produce_type');
    });

    test('three misses end the review with the corrected answer', () async {
      for (var i = 0; i < 3; i++) {
        tutor.answers.add(
          llmCheck(
            Verdict.offTarget,
            ladder: const LlmLadder(
              h1: 'Anlam başka.',
              h2: '',
              h3: '',
              h4: 'Bada kolu.',
            ),
          ),
        );
      }
      await startCard();
      controller().switchInput();
      for (final answer in ['Sima.', 'Dero.', 'Kolu dero.']) {
        await controller().submit(answer);
      }
      final phase = card().phase as CardEnded;
      expect(phase.outcome, isA<NotRecalled>());
      // H4 is the sentence itself: no separate correction.
      expect(phase.correction, isNull);
      await finishCard();
      expect((await attempts()).last.rating, ReviewRating.again.code);
    });
  });

  group('a correct answer without the target (docs/03 §0.2)', () {
    test('asks again without a miss; then the target is Hard', () async {
      await startCard();
      controller().switchInput();
      await controller().submit('Sima kolu.');
      expect(card().last!.feedback, AnswerFeedback.withoutTarget);
      expect(card().canReveal, isTrue);
      expect(card().hints, isEmpty);
      await controller().submit('Bada kolu.');
      expect((card().phase as CardEnded).outcome, isA<Recalled>());
      await finishCard();
      final stored = await attempts();
      expect(stored.map((a) => a.verdict), ['acceptable_variant', 'correct']);
      expect(stored.first.targetOk, isFalse);
      expect(stored.last.rating, ReviewRating.hard.code);
    });
  });

  group('"yanlış duyuldu" (docs/03 §0.3)', () {
    test('the typed answer replaces what was heard, same attempt', () async {
      tutor.answers.add(
        llmCheck(
          Verdict.wrong,
          ladder: const LlmLadder(h1: 'Bir kelime.', h2: '', h3: '', h4: 'x'),
        ),
      );
      await startCard();
      await say('bada kulu');
      expect(card().last!.feedback, AnswerFeedback.tryAgain);
      expect(card().canRetype, isTrue);

      await controller().retype('Bada kolu.');
      final phase = card().phase as CardEnded;
      // The miss is gone: recalled on the first try.
      expect(phase.outcome, isA<Recalled>());
      expect((phase.outcome as Recalled).firstTry, isTrue);

      await finishCard();
      final attempt = (await attempts()).single;
      expect(attempt.activity, 'card.produce_speak');
      expect(attempt.verdict, 'correct');
      expect(attempt.rating, ReviewRating.good.code);
      expect(attempt.response, containsPair('source', 'typed'));
      expect(attempt.response, containsPair('transcript', 'bada kulu'));
      expect(attempt.response, containsPair('asr_override', true));
    });

    test('typed over, the hints are those before what was heard', () async {
      tutor.answers.addAll([
        llmCheck(
          Verdict.wrong,
          ladder: const LlmLadder(h1: 'İlk.', h2: '', h3: '', h4: 'x'),
        ),
        llmCheck(
          Verdict.wrong,
          ladder: const LlmLadder(h1: 'İkinci.', h2: 'Yer.', h3: '', h4: 'y'),
        ),
      ]);
      await startCard();
      await say('bada kulu');
      await say('kolu bada kulu');
      expect(card().hints, const [
        Hint.written('İkinci.'),
        Hint.written('Yer.'),
      ]);

      // Correct without the target: the miss before stays, with its hint.
      await controller().retype('Sima kolu.');
      expect(card().last!.feedback, AnswerFeedback.withoutTarget);
      expect(card().hints, const [Hint.written('İlk.')]);
    });

    test('a typed answer cannot be typed over', () async {
      tutor.answers.add(llmCheck(Verdict.wrong));
      await startCard();
      controller().switchInput();
      await controller().submit('Bada kolo.');
      expect(card().canRetype, isFalse);
      await controller().retype('Bada kolu.');
      expect(card().phase, isA<CardAsking>());
      expect(card().last!.text, 'Bada kolo.');
    });

    test('nothing heard does not count; it can be said again', () async {
      await startCard();
      await say('');
      expect(card().last!.feedback, AnswerFeedback.unheard);
      expect(card().canReveal, isFalse);
      await say('bada kolu');
      expect((card().phase as CardEnded).outcome, isA<Recalled>());
      await finishCard();
      final stored = await attempts();
      expect(stored.map((a) => a.verdict), ['unintelligible', 'correct']);
      // Nothing heard is not a miss: still the first try.
      expect(stored.last.rating, ReviewRating.good.code);
    });
  });

  group('without the LLM (docs/03 §0.5 step 4, docs/07 §7)', () {
    test('the alignment judges and its template gives the hints', () async {
      tutor.failure = TutorFailure.network;
      await startCard();
      controller().switchInput();
      await controller().submit('Kolu.');
      final view = card();
      expect(view.offline, TutorFailure.network);
      expect(view.last!.feedback, AnswerFeedback.tryAgain);
      expect(view.hints, const [Hint.kind(HintKind.missingWord)]);
      controller().nextHint();
      expect(card().hints.last, isA<PlaceHint>());
      await controller().submit('Bada kolu.');
      await finishCard();
      final first = (await attempts()).first;
      expect(first.verdict, 'wrong');
      expect(first.llm, {
        'route': 'answer_check',
        'pending': false,
        'code': 'network',
      });
    });

    test('undecided waits for the LLM and is Hard', () async {
      tutor.failure = TutorFailure.quota;
      await startCard();
      controller().switchInput();
      await controller().submit('Bada dero.');
      final phase = card().phase as CardEnded;
      expect(phase.outcome, isA<Undecided>());
      await finishCard();
      final attempt = (await attempts()).single;
      expect(attempt.verdict, 'uncertain');
      expect(attempt.rating, ReviewRating.hard.code);
      expect(attempt.llm, containsPair('pending', true));
      expect(attempt.llm, containsPair('code', 'quota'));
    });
  });

  group('the LLM', () {
    test('not sure: "did you mean"; a yes counts as correct', () async {
      await startCard();
      controller().switchInput();
      await controller().submit('Bada kolum.');
      expect(card().phase, isA<CardConfirming>());
      expect(card().last!.text, 'Bada kolum.');
      controller().confirm();
      expect((card().phase as CardEnded).outcome, isA<Recalled>());
      await finishCard();
      expect((await attempts()).single.verdict, 'uncertain');
    });

    test('not sure: a corrected answer replaces it', () async {
      await startCard();
      controller().switchInput();
      await controller().submit('Bada kolum.');
      await controller().retype('Bada kolu.');
      await finishCard();
      final attempt = (await attempts()).single;
      expect(attempt.verdict, 'correct');
      expect(attempt.response, containsPair('corrected_from', 'Bada kolum.'));
    });

    test('an accepted answer is learned for next time', () async {
      tutor.answers.add(llmCheck(Verdict.acceptableVariant, targetOk: true));
      await startCard();
      controller().switchInput();
      await controller().submit('Bada kolu ya.');
      expect((card().phase as CardEnded).outcome, isA<Recalled>());
      await finishCard();
      expect(tutor.asked, hasLength(1));

      // A new session: the same answer matches without the LLM.
      container.dispose();
      containerMade = false;
      final cards = await db.select(db.cards).get();
      await db
          .update(db.cards)
          .write(
            CardsCompanion(
              due: Value(cardNow.subtract(const Duration(days: 1))),
            ),
          );
      expect(cards, hasLength(1));
      await start();
      expect(current(), isA<CardSessionCard>());
      controller().switchInput();
      await controller().submit('Bada kolu ya.');
      expect(tutor.asked, hasLength(1));
      expect((card().phase as CardEnded).outcome, isA<Recalled>());
    });
  });

  group('answers are spoken by default (I-05)', () {
    test('silent mode types, and the new card is a typed card', () async {
      profiles.silentMode = true;
      await start();
      // Silent: nothing plays by itself.
      await pumpEventQueue();
      expect(player.played, isEmpty);
      controller().begin();
      expect(card().input, AnswerInput.type);
      await controller().startSpeaking();
      expect(recorder.starts, 0);
      await controller().submit('Bada kolu.');
      await finishCard();
      expect((await attempts()).single.activity, 'card.produce_type');
      expect((await db.select(db.cards).get()).single.mode, 'type');
    });

    test('without audio consent nothing is recorded', () async {
      profiles.audioConsent = false;
      await startCard();
      expect(card().canSpeak, isFalse);
      expect(card().input, AnswerInput.type);
      controller().switchInput();
      expect(card().input, AnswerInput.type);
    });

    test('a failed recognition leaves typing open', () async {
      speech.failure = SpeechFailure.quota;
      await startCard();
      await say('bada kolu');
      expect(card().phase, isA<CardAsking>());
      expect(card().speechFailure, SpeechFailure.quota);
      expect(await attempts(), isEmpty);
    });
  });

  group('the session', () {
    test('reviews due cards first, then the new items', () async {
      final repository = DriftCardRepository(
        db,
        now: () => cardNow.subtract(const Duration(days: 3)),
      );
      final due = await repository.introduce(
        userId: FakeAuthRepository.id,
        courseId: FakeAssessmentRepository.zzCourse.id,
        itemRef: sima,
        mode: CardMode.speak,
      );
      final state = await start();
      final view = (state as CardSessionCard).view;
      expect(view.prompt, 'Sima dero de.');
      expect(view.total, 3);
      speech.heard = 'sima dero';
      await controller().startSpeaking();
      await controller().stopSpeaking();
      await finishCard();
      final attempt = (await attempts()).single;
      expect(attempt.cardId, due.id);
      expect(current(), isA<CardSessionIntroduction>());
    });

    test('what the learner asked for is introduced first (A19)', () async {
      await db
          .into(db.personalItems)
          .insert(
            PersonalItemsCompanion.insert(
              id: 'p1',
              profileId: FakeAuthRepository.id,
              courseId: FakeAssessmentRepository.zzCourse.id,
              kind: 'sentence',
              textL2: 'Kolu sima dero.',
              source: 'gap',
              glossL1: const Value('kolu sima dero demek istedim'),
            ),
          );
      final state = await start();
      final view = (state as CardSessionIntroduction).view;
      expect(view.headword, 'Kolu sima dero.');
      expect(view.meaning, 'kolu sima dero demek istedim');
      expect(view.total, 4);
      controller()
        ..begin()
        ..switchInput();
      expect(card().prompt, 'kolu sima dero demek istedim');
      await controller().submit('Kolu sima dero.');
      expect((card().phase as CardEnded).outcome, isA<Recalled>());
      await finishCard();
      expect((await db.select(db.cards).get()).single.itemRef, 'personal:p1');
    });

    test('ends with what was done', () async {
      await start();
      for (final answer in ['Bada kolu.', 'Sima dero.', 'Dero kolu.']) {
        controller()
          ..begin()
          ..switchInput();
        await controller().submit(answer);
        await finishCard();
      }
      expect(
        current(),
        const CardSessionState.done(reviewed: 0, introduced: 3),
      );
    });

    test('leaving keeps an ended review, not one under way', () async {
      await startCard();
      await say('bada kolu');
      await controller().leave();
      expect(await attempts(), hasLength(1));

      container.dispose();
      containerMade = false;
      await start();
      controller()
        ..begin()
        ..switchInput();
      tutor.answers.add(llmCheck(Verdict.wrong));
      await controller().submit('Sima.');
      await controller().leave();
      expect(await attempts(), hasLength(1));
    });

    test('nothing due and nothing new: an empty session', () async {
      profiles.dailyBudget = const Duration(minutes: 30);
      final repository = DriftCardRepository(db, now: () => cardNow);
      for (final key in [bada, sima, deroKolu]) {
        await repository.introduce(
          userId: FakeAuthRepository.id,
          courseId: FakeAssessmentRepository.zzCourse.id,
          itemRef: key,
          mode: CardMode.speak,
        );
      }
      await db
          .update(db.cards)
          .write(
            CardsCompanion(due: Value(cardNow.add(const Duration(days: 2)))),
          );
      expect(await start(), const CardSessionState.empty());
    });

    test('without the packs there is no session', () async {
      await db.delete(db.contentPacks).go();
      expect(await start(), const CardSessionState.unavailable());
    });
  });
}
