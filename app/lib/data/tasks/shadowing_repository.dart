import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/tables/sync_columns.dart';
import 'package:dilbaz_app/data/speech/transcript.dart';
import 'package:dilbaz_app/data/tutor/pron_check.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// A pronunciation tag of the pair pack: how much it hurts understanding
/// (docs/02 §6) and what it is, in the learner's language.
typedef PronTag = ({double severity, String description});

/// Shadowing (A07, ADR-0011): the pair's pronunciation tags, and each try
/// as an attempt, written once (I-03). The audio is not kept, as with a
/// card's answer; what was recognized and heard is.
abstract interface class ShadowingRepository {
  /// The pronunciation tags of the imported pair pack, by code.
  Future<Map<String, PronTag>> pronunciationTags();

  /// A try at sentence [itemRef]; its attempt id. A second try follows
  /// [parentAttemptId]. [transcript] and [heard] are null when they could
  /// not be had; [errorTags] are the problems heard, shown or not.
  Future<String> recordTry({
    required String userId,
    required String courseId,
    required String deviceId,
    required String itemRef,
    required String reference,
    required String clip,
    required Duration duration,
    required DateTime at,
    required List<String> errorTags,
    Transcript? transcript,
    HeardPronunciation? heard,
    String? parentAttemptId,
  });
}

String _uuidV7() => const Uuid().v7();

class DriftShadowingRepository implements ShadowingRepository {
  new(this._db, {this._now = nowUtc, this._newId = _uuidV7});

  final AppDatabase _db;
  final DateTime Function() _now;
  final String Function() _newId;

  static const activity = 'shadowing';
  static const _attempts = 'attempts';
  static const _errorTag = 'error_tag';
  static const _pronunciation = 'pronunciation';

  @override
  Future<Map<String, PronTag>> pronunciationTags() async => {
    for (final MapEntry(:key, :value) in (await _db.contentDao.pairEntries(
      _errorTag,
    )).entries)
      if (value case {
        'category': _pronunciation,
        'severity': final num severity,
        'description': final String description,
      })
        key: (severity: severity.toDouble(), description: description),
  };

  @override
  Future<String> recordTry({
    required String userId,
    required String courseId,
    required String deviceId,
    required String itemRef,
    required String reference,
    required String clip,
    required Duration duration,
    required DateTime at,
    required List<String> errorTags,
    Transcript? transcript,
    HeardPronunciation? heard,
    String? parentAttemptId,
  }) => _db.transaction(() async {
    final id = _newId();
    await _db
        .into(_db.attempts)
        .insert(
          AttemptsCompanion.insert(
            id: id,
            profileId: userId,
            courseId: courseId,
            deviceId: deviceId,
            activity: activity,
            itemRef: Value(itemRef),
            parentAttemptId: Value(parentAttemptId),
            prompt: {'reference': reference, 'clip': clip},
            response: {
              'source': 'asr',
              'text': ?transcript?.text,
              if (transcript != null)
                'asr': {
                  'provider': transcript.provider,
                  'model': transcript.model,
                },
            },
            errorTags: Value(errorTags),
            llm: Value(heard?.toJson()),
            durationMs: Value(duration.inMilliseconds),
            createdAtClient: at,
            createdAt: Value(_now()),
            pendingPush: const Value(true),
          ),
        );
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            targetTable: _attempts,
            rowId: id,
            op: 'insert',
          ),
        );
    return id;
  });
}
