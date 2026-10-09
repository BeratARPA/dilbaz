import 'dart:async';

import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/assessment_repository.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/placement_bank.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/repositories/profile_repository_provider.dart';
import 'package:dilbaz_app/data/tasks/monthly_test_repository.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/features/placement/application/placement_controller.dart';
import 'package:dilbaz_app/features/placement/application/placement_state.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/pack_fixture.dart';
import '../../helpers/placement_fixture.dart';

void main() {
  late AppDatabase db;
  late FakeProfileRepository profiles;
  late FakePackAudio audio;
  late FakeClipPlayer player;
  late ProviderContainer container;

  Future<void> course() => db
      .into(db.courses)
      .insert(
        CoursesCompanion.insert(
          id: 'course-1',
          profileId: FakeAuthRepository.id,
          l2: 'zz',
          pairPack: 'qq-zz',
          levelEstimates: const Value({
            'overall': {'low': 2, 'high': 2, 'confidence': 'low'},
          }),
        ),
      );

  Future<void> start({
    PlacementBank? bank,
    bool signedIn = true,
    bool withCourse = true,
  }) async {
    if (withCourse) await course();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: signedIn),
        ),
        assessmentRepositoryProvider.overrideWithValue(
          DriftAssessmentRepository(db),
        ),
        monthlyTestRepositoryProvider.overrideWithValue(
          DriftMonthlyTestRepository(db),
        ),
        placementBankRepositoryProvider.overrideWithValue(
          FakeBankRepository(bank),
        ),
        packAudioProvider.overrideWithValue(audio),
        clipPlayerOverride(player),
        profileRepositoryProvider.overrideWithValue(profiles),
        placementSeedProvider.overrideWithValue(7),
      ],
    )..listen(placementControllerProvider, (_, _) {});
    await container.read(placementControllerProvider.future);
  }

  setUp(() {
    db = memoryDatabase();
    profiles = FakeProfileRepository(onboarded: true);
    audio = FakePackAudio();
    player = FakeClipPlayer();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  PlacementController controller() =>
      container.read(placementControllerProvider.notifier);
  PlacementState? state() => container.read(placementControllerProvider).value;

  /// Answers every word: yes to real words, no to made-up ones.
  void answerWords(PlacementBank bank) {
    controller()
      ..begin()
      ..startPart();
    final known = {for (final word in bank.words) word.word: word.band != null};
    for (var now = state(); now is PlacementWord; now = state()) {
      controller().answerWord(known: known[now.word]!);
    }
  }

  /// Answers every question with the right choice, or with "not sure".
  void answerGrammar({bool sure = true}) {
    controller().startPart();
    for (var now = state(); now is PlacementQuestion; now = state()) {
      controller().choose(
        sure
            ? now.options.firstWhere((option) => option.startsWith('right'))
            : null,
      );
    }
  }

  group('PlacementController (docs/06-assessment.md §2)', () {
    test('without a learner, a course or a test there is nothing', () async {
      await start(bank: zzBank(), signedIn: false);
      expect(state(), const PlacementState.unavailable());
      container.dispose();
      await db.delete(db.courses).go();

      await start(bank: zzBank(), withCourse: false);
      expect(state(), const PlacementState.unavailable());
      container.dispose();

      await start();
      expect(state(), const PlacementState.unavailable());
    });

    test('the overview names the parts the device holds', () async {
      await start(bank: zzBank());
      expect(
        state(),
        const PlacementState.overview(parts: PlacementPart.values),
      );
      container.dispose();
      await db.delete(db.courses).go();

      await start(bank: zzBank(grammar: false, dictation: false));
      expect(
        state(),
        const PlacementState.overview(parts: [PlacementPart.words]),
      );
    });

    test('each word comes once, in the order of the seed', () async {
      final bank = zzBank();
      await start(bank: bank);
      controller().begin();
      expect(
        state(),
        const PlacementState.partIntro(part: PlacementPart.words),
      );
      controller().startPart();

      final seen = <String>[];
      for (var now = state(); now is PlacementWord; now = state()) {
        expect((now.number, now.total), (seen.length + 1, 12));
        seen.add(now.word);
        controller().answerWord(known: false);
      }
      expect(seen.toSet(), {for (final word in bank.words) word.word});
      expect(
        seen,
        SeededRandom(7).shuffled([for (final word in bank.words) word.word]),
      );
      expect(
        state(),
        const PlacementState.partIntro(part: PlacementPart.grammar),
      );
    });

    test(
      'a right choice asks from a level up, any other from one down',
      () async {
        final bank = zzBank();
        await start(bank: bank);
        answerWords(bank);
        controller().startPart();

        final first = state()! as PlacementQuestion;
        expect(first.number, 1);
        expect(first.stem, startsWith('A2 '));
        expect(first.options, hasLength(3));
        controller().choose(
          first.options.firstWhere((o) => o.startsWith('right')),
        );

        final second = state()! as PlacementQuestion;
        expect(second.stem, startsWith('B1 '));
        // Not sure is not right.
        controller().choose(null);

        final third = state()! as PlacementQuestion;
        expect(third.number, 3);
        expect(third.stem, startsWith('A2 '));
      },
    );

    test('a sentence is heard before it is written, twice at most', () async {
      final bank = zzBank();
      await start(bank: bank);
      answerWords(bank);
      answerGrammar();
      controller().startPart();
      expect(
        state(),
        const PlacementState.listening(number: 1, total: 2, playsLeft: 2),
      );

      controller().write('bada kolu');
      expect(state(), isA<PlacementListening>());
      expect((state()! as PlacementListening).number, 1);

      await controller().listen();
      expect(audio.fetched, ['zz/1/v1/one.mp3']);
      expect(player.played, ['/clips/zz/1/v1/one.mp3']);
      expect(
        state(),
        const PlacementState.listening(
          number: 1,
          total: 2,
          playsLeft: 1,
          heard: true,
        ),
      );
      await controller().listen();
      await controller().listen();
      expect(player.played, hasLength(2));
      expect((state()! as PlacementListening).playsLeft, 0);

      controller().write('Bada kolu.');
      expect(
        state(),
        const PlacementState.listening(number: 2, total: 2, playsLeft: 2),
      );
    });

    test('a clip that is still playing is not played again', () async {
      final bank = zzBank();
      await start(bank: bank);
      answerWords(bank);
      answerGrammar();
      controller().startPart();
      player.release = Completer();

      final playing = controller().listen();
      await pumpEventQueue();
      expect((state()! as PlacementListening).playing, isTrue);
      await controller().listen();
      player.release!.complete();
      await playing;

      expect(player.played, hasLength(1));
      expect((state()! as PlacementListening).playing, isFalse);
      expect((state()! as PlacementListening).heard, isTrue);
    });

    test('a clip that cannot be had is reported and can be left', () async {
      final bank = zzBank();
      await start(bank: bank);
      answerWords(bank);
      answerGrammar();
      controller().startPart();

      audio.failure = PackFailure.network;
      await controller().listen();
      expect(
        state(),
        const PlacementState.listening(
          number: 1,
          total: 2,
          playsLeft: 2,
          failure: PackFailure.network,
        ),
      );
      audio.failure = null;
      player.works = false;
      await controller().listen();
      expect((state()! as PlacementListening).failure, PackFailure.damaged);
      expect((state()! as PlacementListening).playsLeft, 2);

      controller().skipDictation();
      await pumpEventQueue();
      final report = (state()! as PlacementDone).report!;
      expect(report.listeningLevel, isNull);
      expect(report.grammarLevel, isNotNull);
      final saved = await db.select(db.assessments).getSingle();
      expect(saved.results.containsKey('dictation'), isFalse);
      expect(saved.results.containsKey('grammar'), isTrue);
    });

    test('the whole test is saved as one assessment', () async {
      final bank = zzBank();
      await start(bank: bank);
      answerWords(bank);
      answerGrammar();
      controller().startPart();
      for (final sentence in bank.dictation) {
        await controller().listen();
        controller().write(sentence.text.toUpperCase());
      }
      expect(state(), const PlacementState.saving());
      await pumpEventQueue();

      // Every real word known, no made-up one: the top of the scale. Every
      // grammar choice right: the top of the bank, open upwards.
      expect(
        state(),
        PlacementState.done(
          report: PlacementReport(
            start: CefrLevel.b1,
            vocabulary: 5000,
            vocabularyLevel: LevelEstimate.at(
              CefrLevel.b2,
              source: PlacementOutcome.source,
            ),
            grammarLevel: LevelEstimate.between(
              CefrLevel.b1,
              CefrLevel.c2,
              source: PlacementOutcome.source,
            ),
            listeningLevel: LevelEstimate.between(
              CefrLevel.a2,
              CefrLevel.c2,
              source: PlacementOutcome.source,
            ),
            // No recording yet: the baseline is offered.
            offerBaseline: true,
          ),
        ),
      );
      final saved = await db.select(db.assessments).getSingle();
      expect(saved.kind, 'placement');
      expect(saved.results.keys, {
        'version',
        'seed',
        'xlex',
        'grammar',
        'dictation',
        'duration_ms',
      });
      final xlex = saved.results['xlex']! as Map<String, Object?>;
      expect(xlex['score'], 5000);
      expect(xlex['answers'], hasLength(12));
      final sentences =
          (saved.results['dictation']! as Map<String, Object?>)['sentences']!
              as List<Object?>;
      expect(sentences.first, {
        'key': 'zz.pdict.a.1',
        'level': 'A1',
        'typed': 'BADA KOLU.',
        'plays': 1,
        'words': 2,
        'errors': 0,
        'slips': 0,
      });
      final course = await db.select(db.courses).getSingle();
      expect(course.vocabEstimate, 5000);
      expect(
        (course.levelEstimates['overall']! as Map<String, Object?>)['source'],
        'placement',
      );
      // The course went to the server right away.
      expect(profiles.pushes, 1);
    });

    test('leaving before a part is finished saves nothing', () async {
      await start(bank: zzBank());
      controller()
        ..begin()
        ..startPart()
        ..answerWord(known: true);

      await controller().leave();

      expect(state(), const PlacementState.done());
      expect(await db.select(db.assessments).get(), isEmpty);
    });

    test('leaving keeps the parts that were finished', () async {
      final bank = zzBank();
      await start(bank: bank);
      answerWords(bank);
      controller()
        ..startPart()
        ..choose(null);

      await controller().leave();

      final report = (state()! as PlacementDone).report!;
      expect(report.vocabularyLevel, isNotNull);
      expect(report.grammarLevel, isNull);
      final saved = await db.select(db.assessments).getSingle();
      expect(saved.results.containsKey('grammar'), isFalse);
      // Nothing to leave once the test is over.
      await controller().leave();
      expect(await db.select(db.assessments).get(), hasLength(1));
    });

    test('the second test takes the next version', () async {
      final bank = zzBank();
      await start(bank: bank);
      answerWords(bank);
      await controller().leave();
      container.dispose();
      final repository = FakeBankRepository(bank);
      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(signedIn: true),
          ),
          assessmentRepositoryProvider.overrideWithValue(
            DriftAssessmentRepository(db),
          ),
          monthlyTestRepositoryProvider.overrideWithValue(
            DriftMonthlyTestRepository(db),
          ),
          placementBankRepositoryProvider.overrideWithValue(repository),
          profileRepositoryProvider.overrideWithValue(profiles),
          clipPlayerOverride(FakeClipPlayer()),
        ],
      )..listen(placementControllerProvider, (_, _) {});
      await container.read(placementControllerProvider.future);

      expect(repository.taken, [1]);
    });

    test('taken again, a part left out keeps its estimate', () async {
      final bank = zzBank();
      await start(bank: bank);
      answerWords(bank);
      answerGrammar(sure: false);
      await controller().leave();
      final first = await db.select(db.courses).getSingle();
      expect((state()! as PlacementDone).report!.retake, isFalse);
      container.dispose();

      await start(bank: bank, withCourse: false);
      expect(
        state(),
        const PlacementState.overview(
          parts: PlacementPart.values,
          retake: true,
        ),
      );
      answerWords(bank);
      await controller().leave();

      final report = (state()! as PlacementDone).report!;
      expect(report.retake, isTrue);
      expect(report.grammarLevel, isNull);
      expect(
        report.vocabularyLevel,
        LevelEstimate.at(CefrLevel.b2, source: PlacementOutcome.source),
      );
      // The grammar of the first test still holds the start down.
      expect(report.start, CefrLevel.a0);
      final course = await db.select(db.courses).getSingle();
      expect(course.levelEstimates['grammar'], first.levelEstimates['grammar']);
      expect(
        LevelEstimate.fromJson(
          course.levelEstimates['overall']! as Map<String, Object?>,
        ).reached,
        CefrLevel.a0,
      );
      expect(await db.select(db.assessments).get(), hasLength(2));
    });

    test('the baseline is offered while the course has no recording', () async {
      final bank = zzBank();
      await start(bank: bank);
      answerWords(bank);
      await controller().leave();
      expect((state()! as PlacementDone).report!.offerBaseline, isTrue);
      container.dispose();

      // A recording made since: the baseline, or a monthly test.
      await DriftMonthlyTestRepository(db, now: () => DateTime.utc(2026)).save(
        id: 'monthly-1',
        userId: FakeAuthRepository.id,
        courseId: 'course-1',
        baseline: true,
        tasks: const [
          (
            taskRef: 'anc-1',
            recordingId: 'recording-1',
            anchor: true,
            metrics: null,
            clauses: null,
            errorFree: null,
          ),
        ],
      );
      await start(bank: bank, withCourse: false);
      answerWords(bank);
      await controller().leave();
      expect((state()! as PlacementDone).report!.offerBaseline, isFalse);
    });

    test('actions out of turn change nothing', () async {
      await start(bank: zzBank());
      final overview = state();
      controller()
        ..startPart()
        ..answerWord(known: true)
        ..choose('x')
        ..write('x')
        ..skipDictation();
      await controller().listen();
      expect(state(), overview);
    });
  });
}
