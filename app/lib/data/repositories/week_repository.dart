import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/card_repository.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart';

/// What the learner did in a week (docs/09 §5.13): counts of what was done,
/// nothing about what was not (I-04, I-12).
typedef WeekActivity = ({
  /// The learner's local days with a session.
  Set<DateTime> days,
  Map<Strand, Duration> time,

  /// Cards reviewed, the first card of a new item not counted.
  int cardReviews,

  /// Items whose first card was made this week.
  int newItems,

  /// Sentences written down (A05) and said (A07).
  int dictation,
  int shadowing,

  /// Topics told three times (A12).
  int fluency,

  /// Speaking tasks recorded (A11), and all the speech recorded.
  int speakingTasks,
  Duration speaking,

  /// The monthly recording was made (A23).
  bool monthly,

  /// "Söyleyemedim" notes (A19).
  int captures,
});

/// The week summary's reads (docs/09 §5.13).
abstract interface class WeekRepository {
  /// What was done in [courseId] from [start] up to [end] (UTC).
  Future<WeekActivity> week(String courseId, DateTime start, DateTime end);
}

class DriftWeekRepository implements WeekRepository {
  const new(this._db);

  final AppDatabase _db;

  /// Activity codes of card answers: every mode but dictation's.
  static final List<String> _cardActivities = [
    for (final mode in CardMode.values)
      if (mode != CardMode.dictation) cardActivity(mode),
  ];

  @override
  Future<WeekActivity> week(
    String courseId,
    DateTime start,
    DateTime end,
  ) async {
    final sessions =
        await (_db.select(_db.sessions)..where(
              (t) =>
                  t.courseId.equals(courseId) &
                  t.startedAt.isBiggerOrEqualValue(start) &
                  t.startedAt.isSmallerThanValue(end),
            ))
            .get();
    final time = <Strand, Duration>{};
    final days = <DateTime>{};
    for (final row in sessions) {
      final local = row.startedAt.toLocal();
      days.add(DateTime(local.year, local.month, local.day));
      for (final strand in Strand.values) {
        if (row.strandMs[strand.code] case final num ms) {
          time[strand] =
              (time[strand] ?? Duration.zero) +
              Duration(milliseconds: ms.round());
        }
      }
    }

    final attempts =
        await (_db.select(_db.attempts)..where(
              (t) =>
                  t.courseId.equals(courseId) &
                  t.createdAtClient.isBiggerOrEqualValue(start) &
                  t.createdAtClient.isSmallerThanValue(end),
            ))
            .get();
    var rated = 0;
    var dictation = 0;
    var shadowing = 0;
    var fluency = 0;
    for (final row in attempts) {
      final first = row.parentAttemptId == null;
      switch (row.activity) {
        case final code when _cardActivities.contains(code):
          if (row.rating != null) rated++;
        case 'dictation':
          if (row.rating != null) dictation++;
        case 'shadowing':
          if (first) shadowing++;
        case 'fluency_432':
          if (first) fluency++;
      }
    }

    // An item is new on the day of its first card (A03, A04).
    final firstCard = <String, DateTime>{};
    for (final card in await (_db.select(
      _db.cards,
    )..where((t) => t.courseId.equals(courseId))).get()) {
      if (card.mode == CardMode.dictation.code) continue;
      final seen = firstCard[card.itemRef];
      if (seen == null || card.createdAt.isBefore(seen)) {
        firstCard[card.itemRef] = card.createdAt;
      }
    }
    final newItems = firstCard.values
        .where((at) => !at.isBefore(start) && at.isBefore(end))
        .length;

    final recordings =
        await (_db.select(_db.recordings)..where(
              (t) =>
                  t.courseId.equals(courseId) &
                  t.createdAt.isBiggerOrEqualValue(start) &
                  t.createdAt.isSmallerThanValue(end),
            ))
            .get();
    final captures =
        await (_db.selectOnly(_db.gapEntries)
              ..addColumns([_db.gapEntries.id.count()])
              ..where(
                _db.gapEntries.courseId.equals(courseId) &
                    _db.gapEntries.createdAt.isBiggerOrEqualValue(start) &
                    _db.gapEntries.createdAt.isSmallerThanValue(end),
              ))
            .map((row) => row.read(_db.gapEntries.id.count()) ?? 0)
            .getSingle();

    return (
      days: days,
      time: time,
      // A new item's first rated card is its introduction.
      cardReviews: rated - newItems < 0 ? 0 : rated - newItems,
      newItems: newItems,
      dictation: dictation,
      shadowing: shadowing,
      fluency: fluency,
      speakingTasks: recordings.where((r) => !r.isAssessment).length,
      speaking: Duration(
        milliseconds: recordings.fold(0, (sum, r) => sum + r.durationMs),
      ),
      monthly: recordings.any((r) => r.isAssessment),
      captures: captures,
    );
  }
}
