import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/card_feedback_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pack_fixture.dart';

const userId = '11111111-1111-4111-8111-111111111111';
final t0 = DateTime.utc(2026, 10, 1, 9);

const Map<String, Object?> asked = {
  'ctx': {'l1': 'tr', 'l2': 'zz', 'level': 'A2', 'explain_in': 'l1'},
  'response': {'text': 'Kolu.', 'source': 'typed'},
};

void main() {
  late AppDatabase db;
  late DriftCardFeedbackRepository feedback;
  var next = 0;

  setUp(() {
    db = memoryDatabase();
    next = 0;
    feedback = DriftCardFeedbackRepository(
      db,
      now: () => t0,
      newId: () => 'id-${next++}',
    );
  });
  tearDown(() => db.close());

  Future<void> attempt(
    String id, {
    String device = 'device-1',
    Map<String, Object?>? llm,
    int minute = 0,
  }) => db
      .into(db.attempts)
      .insert(
        AttemptsCompanion.insert(
          id: id,
          profileId: userId,
          courseId: 'course-1',
          deviceId: device,
          activity: 'card.produce_type',
          itemRef: const Value('zz.ws.bada.n.1'),
          prompt: const {'prompt_l1': 'Bada kolu diye sor.'},
          response: const {'text': 'Kolu.', 'source': 'typed'},
          llm: Value(llm),
          createdAtClient: t0.add(Duration(minutes: minute)),
        ),
      );

  test('a dispute is an amendment and a content report, both queued', () async {
    await attempt('attempt-1');
    await feedback.dispute(
      userId: userId,
      attemptId: 'attempt-1',
      itemRef: 'zz.ws.bada.n.1',
      answer: 'Kolu.',
      request: asked,
      targetIntact: false,
      context: const {'carrier': 'zz.sent.0001'},
    );

    final amendment = await db.select(db.attemptAmendments).getSingle();
    expect(amendment.id, 'id-0');
    expect(amendment.kind, 'user_dispute');
    expect(amendment.payload, {
      'answer': 'Kolu.',
      'request': asked,
      'target_intact': false,
    });
    expect(amendment.createdAt, t0);
    expect(amendment.pendingPush, isTrue);
    final report = await db.select(db.contentReports).getSingle();
    expect(report.reason, 'answer');
    expect(report.note, isNull);
    expect(report.context, {
      'carrier': 'zz.sent.0001',
      'attempt_id': 'attempt-1',
      'answer': 'Kolu.',
    });
    final outbox = await db.select(db.outbox).get();
    expect(
      [for (final e in outbox) (e.targetTable, e.rowId, e.op)],
      [
        ('attempt_amendments', 'id-0', 'insert'),
        ('content_reports', 'id-1', 'insert'),
      ],
    );
  });

  test('a report keeps a note only when there is one', () async {
    await feedback.report(
      userId: userId,
      itemRef: 'zz.ws.bada.n.1',
      reason: ReportReason.audio,
      note: '   ',
      context: const {'carrier': 'zz.sent.0001'},
    );
    final report = await db.select(db.contentReports).getSingle();
    expect(
      (report.reason, report.note, report.status),
      ('audio', null, 'open'),
    );
  });

  test('answers wait for the tutor until it has a verdict', () async {
    // Checked without the tutor, with the request to ask again and the
    // engine's word on the target (ADR-0010).
    await attempt(
      'pending',
      llm: {
        'route': 'answer_check',
        'pending': true,
        'request': asked,
        'target_intact': true,
      },
    );
    // Kept before the engine's word was: none.
    await attempt(
      'older',
      minute: 2,
      llm: {'route': 'answer_check', 'pending': true, 'request': asked},
    );
    // Disputed: the dispute's request.
    await attempt('disputed', minute: 1);
    await feedback.dispute(
      userId: userId,
      attemptId: 'disputed',
      itemRef: 'zz.ws.bada.n.1',
      answer: 'Kolu.',
      request: {...asked, 'attempt_no': 2},
      targetIntact: false,
      context: const {},
    );
    // Not waiting: judged, a failure that does not wait, another device.
    await attempt('judged', llm: {'route': 'answer_check', 'pending': false});
    await attempt(
      'not-pending',
      llm: {'route': 'answer_check', 'pending': false, 'code': 'network'},
    );
    await attempt(
      'elsewhere',
      device: 'device-2',
      llm: {'route': 'answer_check', 'pending': true, 'request': asked},
    );

    final waiting = await feedback.waiting('device-1', limit: 10);
    expect(
      [
        for (final (:attemptId, :request, :targetIntact) in waiting)
          [attemptId, request, targetIntact],
      ],
      [
        ['pending', asked, true],
        [
          'disputed',
          {...asked, 'attempt_no': 2},
          false,
        ],
        ['older', asked, null],
      ],
    );
    expect(await feedback.waiting('device-1', limit: 1), hasLength(1));

    await feedback.resolve(
      userId: userId,
      attemptId: 'pending',
      verdict: const {'verdict': 'correct', 'target_ok': true},
    );
    expect(
      [
        for (final check in await feedback.waiting('device-1', limit: 10))
          check.attemptId,
      ],
      ['disputed', 'older'],
    );
    final resolved = await (db.select(
      db.attemptAmendments,
    )..where((t) => t.kind.equals('llm_resolved'))).getSingle();
    expect(resolved.attemptId, 'pending');
    expect(resolved.payload, {'verdict': 'correct', 'target_ok': true});
    expect(
      (await db.select(db.outbox).get()).map((e) => e.targetTable),
      contains('attempt_amendments'),
    );
  });
}
