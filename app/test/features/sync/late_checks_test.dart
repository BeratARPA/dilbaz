import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/card_feedback_repository.dart';
import 'package:dilbaz_app/data/repositories/device_repository.dart';
import 'package:dilbaz_app/data/tutor/answer_check_request.dart';
import 'package:dilbaz_app/data/tutor/tutor_repository.dart';
import 'package:dilbaz_app/features/sync/application/late_checks.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

import '../../helpers/card_fixture.dart';
import '../../helpers/pack_fixture.dart';

const userId = '11111111-1111-4111-8111-111111111111';
final t0 = DateTime.utc(2026, 10, 1, 9);

const request = AnswerCheckRequest(
  l1: 'tr',
  l2: 'zz',
  level: CefrLevel.a2,
  explainInL1: true,
  itemKey: 'zz.ws.bada.n.1',
  prompt: 'Bada kolu diye sor.',
  reference: 'Bada kolu.',
  variants: ['Kolu bada.'],
  alternatives: [],
  targetSpan: 'bada',
  answer: 'Bada dero.',
  typed: true,
  attemptNo: 1,
);

void main() {
  late AppDatabase db;
  late FakeTutorRepository tutor;
  late LateChecks checks;

  setUp(() async {
    db = memoryDatabase();
    tutor = FakeTutorRepository();
    final devices = DriftDeviceRepository(db, newId: () => 'device-1');
    await devices.deviceId(userId);
    checks = LateChecks(
      feedback: DriftCardFeedbackRepository(db, now: () => t0),
      tutor: tutor,
      devices: devices,
    );
  });
  tearDown(() => db.close());

  /// An answer checked without the tutor on this device.
  Future<void> waiting(String id, {String answer = 'Bada dero.'}) => db
      .into(db.attempts)
      .insert(
        AttemptsCompanion.insert(
          id: id,
          profileId: userId,
          courseId: 'course-1',
          deviceId: 'device-1',
          activity: 'card.produce_type',
          prompt: const {},
          response: {'text': answer, 'source': 'typed'},
          verdict: const Value('uncertain'),
          llm: Value({
            'route': 'answer_check',
            'pending': true,
            'code': 'network',
            'request': request.copyWith(answer: answer).toJson(),
          }),
          createdAtClient: t0,
        ),
      );

  Future<List<AttemptAmendmentRow>> verdicts() => (db.select(
    db.attemptAmendments,
  )..where((t) => t.kind.equals('llm_resolved'))).get();

  test('the tutor gets the kept request; its verdict is stored', () async {
    await waiting('attempt-1');
    tutor.answers.add(
      llmCheck(Verdict.acceptableVariant, targetOk: true, tags: const ['x']),
    );

    expect(await checks.run(userId), 1);

    expect(tutor.asked, [request]);
    final verdict = (await verdicts()).single;
    expect(verdict.attemptId, 'attempt-1');
    expect(verdict.payload, {
      'verdict': 'acceptable_variant',
      'target_ok': true,
      'error_tags': ['x'],
      'provider': 'fake',
      'model': 'fake-model',
      'catalog': 'qq-zz@1',
      'confidence': 0.9,
    });
    // Settled: it is not asked again.
    expect(await checks.run(userId), 0);
    expect(tutor.asked, hasLength(1));
  });

  test('a refusal settles it too; an unreachable tutor is tried again '
      'later', () async {
    await waiting('attempt-1');
    await waiting('attempt-2', answer: 'Dero bada.');

    tutor.failure = TutorFailure.network;
    expect(await checks.run(userId), 0);
    // Out of reach: the rest waits for the next sync.
    expect(tutor.asked, hasLength(1));
    expect(await verdicts(), isEmpty);

    tutor.failure = TutorFailure.refused;
    expect(await checks.run(userId), 2);
    expect(
      [for (final v in await verdicts()) v.payload],
      [
        {'code': 'refused'},
        {'code': 'refused'},
      ],
    );
  });

  test('a run checks a handful at most', () async {
    for (var i = 0; i < LateChecks.perRun + 2; i++) {
      await waiting('attempt-$i');
    }
    tutor.failure = TutorFailure.invalid;
    expect(await checks.run(userId), LateChecks.perRun);
    expect(await checks.run(userId), 2);
  });
}
