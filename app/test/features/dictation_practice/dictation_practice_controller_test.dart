import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/features/cards/application/card_plan.dart';
import 'package:dilbaz_app/features/dictation_practice/application/dictation_practice_controller.dart';
import 'package:dilbaz_app/features/dictation_practice/application/dictation_practice_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/card_fixture.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_speech.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';

/// Makes "Bada kolu." a sentence the learner can understand (I-06): both
/// lemmas in the lexicon's first band, and a vocabulary test that knows
/// that band.
Future<void> understood(
  AppDatabase db,
  FakeAssessmentRepository assessments,
) async {
  await db.batch(
    (batch) => batch.insertAll(db.contentItems, [
      item(
        'zz.lemma.bada',
        'lemma',
        packId: 'zz@1',
        text: 'bada',
        lemmas: ['bada'],
        rank: 10,
      ),
      item(
        'zz.lemma.kolu',
        'lemma',
        packId: 'zz@1',
        text: 'kolu',
        lemmas: ['kolu'],
        rank: 300,
      ),
    ]),
  );
  assessments.xlex = const XlexResult(
    score: 1000,
    bandRates: {1: 1, 2: 1, 3: 1, 4: 1, 5: 1},
    falseAlarmRate: 0,
  );
}

/// The card session's plan, read the way the session reads it.
final _plan = FutureProvider<CardPlan?>(planCards);

void main() {
  late AppDatabase db;
  late FakeAssessmentRepository assessments;
  late FakePackAudio audio;
  late FakeClipPlayer player;
  late ProviderContainer container;
  var made = false;

  setUp(() async {
    db = memoryDatabase();
    await installCardPacks(db);
    assessments = FakeAssessmentRepository(open: false);
    audio = FakePackAudio();
    player = FakeClipPlayer();
    made = false;
  });

  tearDown(() async {
    if (made) container.dispose();
    await db.close();
  });

  DictationPracticeController controller() =>
      container.read(dictationPracticeControllerProvider.notifier);
  DictationPracticeState? current() =>
      container.read(dictationPracticeControllerProvider).value;

  Future<DictationPracticeState> start({DateTime? now}) async {
    container = ProviderContainer(
      overrides: cardSessionOverrides(
        db: db,
        profiles: FakeProfileRepository(onboarded: true),
        tutor: FakeTutorRepository(),
        speech: FakeSpeechRepository(),
        recorder: FakeAnswerRecorder(),
        audio: audio,
        player: player,
        assessments: assessments,
        clock: now == null ? null : () => now,
      ),
    )..listen(dictationPracticeControllerProvider, (_, _) {});
    made = true;
    return await container.read(dictationPracticeControllerProvider.future);
  }

  Future<List<AttemptRow>> attempts() => (db.select(
    db.attempts,
  )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get();

  test(
    'without a sentence the learner can understand, nothing (I-06)',
    () async {
      expect(await start(), const DictationPracticeState.nothingToHear());
    },
  );

  test('heard, written, checked word by word; misses by kind', () async {
    await understood(db, assessments);
    expect(
      await start(),
      const DictationPracticeState.listening(number: 1, total: 1, slow: false),
    );
    // Nothing to check before the sentence is heard (I-01).
    controller().check('bada kolu');
    expect(current(), isA<DictationListening>());

    await controller().listen();
    expect(audio.fetched, ['zz/v1/0001.mp3']);
    expect(player.played, ['/clips/zz/v1/0001.mp3']);
    expect((current()! as DictationListening).heard, isTrue);

    controller().check('badan');
    final checked = current()! as DictationChecked;
    expect(checked.result.words, ['bada', 'kolu']);
    expect(checked.result.marks, [DictationMark.ending, DictationMark.missed]);
    expect(checked.result.errors, 2);
    expect(checked.canTryAgain, isTrue);
  });

  test('a slow second try; the first try rates the card; every try is an '
      'attempt (I-03)', () async {
    await understood(db, assessments);
    await start();
    await controller().listen();
    controller().check('bada');
    controller().tryAgainSlowly();
    expect(
      current(),
      const DictationPracticeState.listening(number: 1, total: 1, slow: true),
    );
    await controller().listen();
    expect(audio.fetched.last, 'zz/v1/0001s.mp3');
    controller().check('Bada kolu.');
    final checked = current()! as DictationChecked;
    expect(checked.result.errors, 0);
    expect(checked.canTryAgain, isFalse);

    await controller().next();
    expect(
      current(),
      const DictationPracticeState.done(
        sentences: 1,
        heardRight: 0,
        misses: {DictationMark.missed: 1},
      ),
    );
    final stored = await attempts();
    expect(stored.map((a) => a.activity), ['dictation', 'dictation']);
    expect(stored.first.verdict, 'wrong');
    expect(stored.first.rating, isNull);
    expect(stored.last.parentAttemptId, stored.first.id);
    expect(stored.last.response, containsPair('slow', true));
    // Rated by the first try: a missed word of two, Again.
    expect(stored.last.rating, ReviewRating.again.code);
    final card = (await db.select(db.cards).get()).single;
    expect(card.mode, 'dictation');
    expect(card.itemRef, badaSentence);
    final session = (await db.select(db.sessions).get()).single;
    expect(session.strandMs.keys, ['language']);
  });

  test('perception tags go with the attempt', () async {
    await understood(db, assessments);
    await start();
    await controller().listen();
    controller().check('badan kolu');
    await controller().next();
    expect((await attempts()).single.errorTags, ['perc.endings']);
  });

  test('the card is due again: it comes first; not a card of the card '
      'session', () async {
    await understood(db, assessments);
    await start();
    await controller().listen();
    controller().check('bada kolu');
    await controller().next();
    container.dispose();

    // Days later the dictation card is due.
    final later = cardNow.add(const Duration(days: 30));
    final again = await start(now: later) as DictationListening;
    expect(again.total, 1);
    final plan = await container.read(_plan.future);
    expect(
      plan!.plan.reviews.map((c) => c.itemKey),
      isNot(contains(badaSentence)),
    );
    expect(
      plan.cards.values.map((c) => c.mode),
      isNot(contains(CardMode.dictation)),
    );
  });

  test('a clip that cannot be had says so and can be tried again', () async {
    await understood(db, assessments);
    await start();
    audio.failure = PackFailure.network;
    await controller().listen();
    expect((current()! as DictationListening).failure, PackFailure.network);
    audio.failure = null;
    await controller().listen();
    expect((current()! as DictationListening).heard, isTrue);
  });

  test('leaving keeps what was checked', () async {
    await understood(db, assessments);
    await start();
    await controller().listen();
    controller().check('bada kolu');
    await controller().leave();
    await controller().leave();
    expect(await attempts(), hasLength(1));
    expect(await db.select(db.sessions).get(), hasLength(1));
    // The content gives the sentence its clips.
    final sentences = await container
        .read(cardContentRepositoryProvider)
        .sentences();
    expect(sentences.single.slowClip, 'zz/v1/0001s.mp3');
  });
}
