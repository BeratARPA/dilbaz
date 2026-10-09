import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/converters.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Why the learner reports the content (`content_reports.reason`).
enum ReportReason {
  /// The Turkish meaning is wrong.
  meaning('meaning'),

  /// The English sentence is wrong or unnatural.
  sentence('sentence'),

  /// The audio is broken or wrong.
  audio('audio'),

  /// "My answer may be right too": a disputed answer.
  answer('answer'),
  other('other');

  new(this.code);

  final String code;
}

/// An answer that waits for the tutor: checked without it, or disputed.
/// `request` is the `tutor/answer_check` body kept for it.
/// An answer waiting for the tutor: its request and the engine's word on
/// its target, which settles a minor error (ADR-0010); null on answers
/// stored before it was kept.
typedef WaitingCheck = ({
  String attemptId,
  Map<String, Object?> request,
  bool? targetIntact,
});

/// What can follow a card's answers once they are stored (docs/03 §0.5
/// steps 4–5, docs/10 §8): the learner's dispute, a report about the
/// content, and the tutor's late verdict. Attempts never change (I-03):
/// these come as amendments and reports, each queued for the server.
abstract interface class CardFeedbackRepository {
  /// "Cevabım da doğru olabilir": [answer], the answer of [attemptId], is
  /// disputed. It is asked again with [request] when the tutor can be
  /// reached, and reported as content to look at ([context]: what the card
  /// showed). Nothing is accepted by the learner's word alone.
  /// [targetIntact] is the engine's word on the answer's target.
  Future<void> dispute({
    required String userId,
    required String attemptId,
    required String itemRef,
    required String answer,
    required Map<String, Object?> request,
    required bool targetIntact,
    required Map<String, Object?> context,
  });

  /// "Bu içerikte hata var".
  Future<void> report({
    required String userId,
    required String itemRef,
    required ReportReason reason,
    required Map<String, Object?> context,
    String? note,
  });

  /// Answers given on [deviceId] that wait for the tutor, oldest first.
  Future<List<WaitingCheck>> waiting(String deviceId, {required int limit});

  /// The tutor's late verdict on [attemptId] (`llm_resolved`): what
  /// `answer_check` said, or the code of why it cannot say.
  Future<void> resolve({
    required String userId,
    required String attemptId,
    required Map<String, Object?> verdict,
  });
}

String _uuidV7() => const Uuid().v7();

class DriftCardFeedbackRepository implements CardFeedbackRepository {
  new(this._db, {this._now = nowUtc, this._newId = _uuidV7});

  final AppDatabase _db;
  final DateTime Function() _now;
  final String Function() _newId;

  static const _insert = 'insert';
  static const disputeKind = 'user_dispute';
  static const resolvedKind = 'llm_resolved';

  Future<void> _amend(
    String userId,
    String attemptId,
    String kind,
    Map<String, Object?> payload,
  ) async {
    final id = _newId();
    await _db
        .into(_db.attemptAmendments)
        .insert(
          AttemptAmendmentsCompanion.insert(
            id: id,
            attemptId: attemptId,
            profileId: userId,
            kind: kind,
            payload: payload,
            createdAt: Value(_now()),
            pendingPush: const Value(true),
          ),
        );
    await _queue(_db.attemptAmendments.actualTableName, id);
  }

  Future<void> _queue(String table, String rowId) => _db
      .into(_db.outbox)
      .insert(
        OutboxCompanion.insert(targetTable: table, rowId: rowId, op: _insert),
      );

  @override
  Future<void> dispute({
    required String userId,
    required String attemptId,
    required String itemRef,
    required String answer,
    required Map<String, Object?> request,
    required bool targetIntact,
    required Map<String, Object?> context,
  }) => _db.transaction(() async {
    await _amend(userId, attemptId, disputeKind, {
      'answer': answer,
      'request': request,
      'target_intact': targetIntact,
    });
    await _report(
      userId: userId,
      itemRef: itemRef,
      reason: ReportReason.answer,
      context: {...context, 'attempt_id': attemptId, 'answer': answer},
    );
  });

  @override
  Future<void> report({
    required String userId,
    required String itemRef,
    required ReportReason reason,
    required Map<String, Object?> context,
    String? note,
  }) => _db.transaction(
    () => _report(
      userId: userId,
      itemRef: itemRef,
      reason: reason,
      context: context,
      note: note,
    ),
  );

  Future<void> _report({
    required String userId,
    required String itemRef,
    required ReportReason reason,
    required Map<String, Object?> context,
    String? note,
  }) async {
    final id = _newId();
    final written = note?.trim();
    await _db
        .into(_db.contentReports)
        .insert(
          ContentReportsCompanion.insert(
            id: id,
            profileId: userId,
            itemRef: itemRef,
            reason: reason.code,
            note: Value(written == null || written.isEmpty ? null : written),
            context: Value(context),
            createdAt: Value(_now()),
            pendingPush: const Value(true),
          ),
        );
    await _queue(_db.contentReports.actualTableName, id);
  }

  @override
  Future<List<WaitingCheck>> waiting(
    String deviceId, {
    required int limit,
  }) async {
    // The request comes from the dispute when there is one: it is the
    // later word on the answer.
    final rows = await _db
        .customSelect(
          r'''
SELECT a.id AS id,
       COALESCE(
         (SELECT json_extract(d.payload, '$.request')
            FROM attempt_amendments d
           WHERE d.attempt_id = a.id AND d.kind = ?
           ORDER BY d.created_at DESC LIMIT 1),
         CASE WHEN json_extract(a.llm, '$.pending') = 1
              THEN json_extract(a.llm, '$.request') END
       ) AS request,
       COALESCE(
         (SELECT json_extract(d.payload, '$.target_intact')
            FROM attempt_amendments d
           WHERE d.attempt_id = a.id AND d.kind = ?
           ORDER BY d.created_at DESC LIMIT 1),
         json_extract(a.llm, '$.target_intact')
       ) AS target_intact
  FROM attempts a
 WHERE a.device_id = ?
   AND NOT EXISTS (SELECT 1 FROM attempt_amendments r
                    WHERE r.attempt_id = a.id AND r.kind = ?)
   AND request IS NOT NULL
 ORDER BY a.created_at_client
 LIMIT ?
''',
          variables: [
            Variable.withString(disputeKind),
            Variable.withString(disputeKind),
            Variable.withString(deviceId),
            Variable.withString(resolvedKind),
            Variable.withInt(limit),
          ],
          readsFrom: {_db.attempts, _db.attemptAmendments},
        )
        .get();
    return [
      for (final row in rows)
        (
          attemptId: row.read<String>('id'),
          request: const JsonObjectConverter().fromSql(
            row.read<String>('request'),
          ),
          // SQLite's JSON gives a boolean as 1 or 0.
          targetIntact: switch (row.read<int?>('target_intact')) {
            null => null,
            final int flag => flag == 1,
          },
        ),
    ];
  }

  @override
  Future<void> resolve({
    required String userId,
    required String attemptId,
    required Map<String, Object?> verdict,
  }) => _db.transaction(() => _amend(userId, attemptId, resolvedKind, verdict));
}
