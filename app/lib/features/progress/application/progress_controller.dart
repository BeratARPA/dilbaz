import 'package:dilbaz_app/core/clock.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/auth_repository_provider.dart';
import 'package:dilbaz_app/data/repositories/card_providers.dart';
import 'package:dilbaz_app/data/repositories/placement_providers.dart';
import 'package:dilbaz_app/data/tasks/task_providers.dart';
import 'package:dilbaz_app/features/progress/application/progress_view.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:json_annotation/json_annotation.dart'
    show CheckedFromJsonException;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'progress_controller.g.dart';

/// A recording's transcript and marks, as the engine reads them; null when
/// it has none yet.
({List<TimedWord> words, SpeechAnnotation annotation})? _speech(
  RecordingRow row,
) {
  final words = row.asr?['words'];
  final merged = row.annotation?['merged'];
  if (words is! List || merged is! Map<String, Object?>) return null;
  try {
    return (
      words: [
        for (final word in words)
          if (word case final Map<String, Object?> json)
            TimedWord.fromJson(json),
      ],
      annotation: SpeechAnnotation.fromJson(merged),
    );
  } on CheckedFromJsonException {
    return null;
  }
}

DateTime _localDay(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime _localMonth(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month);
}

TaskOutcome? _outcome(String? code) => switch (code) {
  'done' => TaskOutcome.done,
  'partial' => TaskOutcome.partial,
  'not_done' => TaskOutcome.notDone,
  _ => null,
};

/// The Progress tab's view (docs/09 §5.11, v1); null before the welcome
/// flow or the packs.
/// Plays a recording of the Progress tab: this device's audio, else the
/// server's, for a recording made on another device (docs/08 §5.2).
@riverpod
class RecordingPlayback extends _$RecordingPlayback {
  /// The audio being fetched, if any.
  @override
  String? build() => null;

  Future<void> play(String audioPath) async {
    state = audioPath;
    final path = await ref.read(recordingFilesProvider).playable(audioPath);
    if (!ref.mounted) return;
    state = null;
    if (path != null) await ref.read(clipPlayerProvider).play(path);
  }
}

@riverpod
Future<ProgressView?> progress(Ref ref) async {
  final userId = ref.watch(authRepositoryProvider).userId;
  if (userId == null) return null;
  final course = await ref.watch(assessmentRepositoryProvider).course(userId);
  final content = ref.watch(cardContentRepositoryProvider);
  final language = await content.language();
  if (course == null || language == null) return null;
  final now = ref.watch(clockProvider)();
  final tasks = ref.watch(taskContentRepositoryProvider);
  final evidence = await ref.watch(cardRepositoryProvider).evidence(course.id);
  final recordings = await ref
      .watch(recordingRepositoryProvider)
      .recordings(course.id);

  // Free production: the items each recording used without error, by day.
  final usable = <UsableItem>[
    for (final item in [
      ...await content.items(),
      ...await content.personalItems(course.id, course.level),
    ])
      if (evidence.containsKey(item.key))
        (key: item.key, kind: item.kind, lemmas: item.lemmas),
  ];
  final useDays = <String, Set<DateTime>>{};
  for (final row in recordings) {
    final speech = _speech(row);
    if (speech == null) continue;
    final day = _localDay(row.createdAt);
    for (final key in usedWithoutError(
      speech.words,
      annotation: speech.annotation,
      items: usable,
      language: language,
    )) {
      (useDays[key] ??= {}).add(day);
    }
  }

  // Can-dos from the tasks' outcomes.
  final speaking = {
    for (final task in await tasks.speakingTasks()) task.key: task,
  };
  final codes = await tasks.canDos();
  final attempts = <CanDoAttempt>[
    for (final row in recordings)
      if ((speaking[row.taskRef], _outcome(row.outcome)) case (
        final task?,
        final outcome?,
      ))
        for (final code in task.canDo)
          (
            code: code,
            day: _localDay(row.createdAt),
            prompt: task.key,
            outcome: outcome,
            scaffolded: task.anchor == null,
          ),
  ];
  final shown = canDoEvidence(
    attempts,
    now: now,
    levels: {for (final canDo in codes) canDo.code: canDo.level},
  );

  // The anchors over the months.
  final anchors = [
    for (final task in speaking.values)
      if (task.anchor != null) task,
  ]..sort((a, b) => a.anchor!.compareTo(b.anchor!));
  return ProgressView(
    counts: countEvidence(
      evidence,
      now: now,
      freeUseDays: {
        for (final MapEntry(:key, :value) in useDays.entries) key: value.length,
      },
    ),
    vocabulary:
        (await ref.watch(assessmentRepositoryProvider).latestXlex(course.id))
            ?.score,
    canDos: [
      for (final canDo in codes)
        (
          summary: canDo.summary,
          status: shown[canDo.code]?.status ?? CanDoStatus.none,
          refresh: shown[canDo.code]?.refresh ?? false,
        ),
    ],
    anchors: [
      for (final task in anchors)
        _anchor(task.title, [
          for (final row in recordings)
            if (row.taskRef == task.key && row.isAssessment) row,
        ]),
    ],
  );
}

AnchorView _anchor(String title, List<RecordingRow> rows) {
  final kept = [
    for (final row in rows)
      if (row.audioPath != null) row,
  ];
  final latest = kept.lastOrNull;
  final first = kept.firstOrNull;
  final previous = latest == null
      ? null
      : kept
            .where(
              (row) =>
                  _localMonth(row.createdAt)
                      .isBefore(_localMonth(latest.createdAt)) &&
                  row != first,
            )
            .lastOrNull;
  AnchorRecording listen(AnchorMoment moment, RecordingRow row) =>
      (moment: moment, day: _localDay(row.createdAt), path: row.audioPath!);
  final byMonth = <DateTime, RecordingRow>{
    for (final row in rows) _localMonth(row.createdAt): row,
  };
  double? number(RecordingRow row, String key) => switch (row.metrics?[key]) {
    final num value => value.toDouble(),
    _ => null,
  };
  return AnchorView(
    title: title,
    recordings: [
      if (first != null) listen(AnchorMoment.first, first),
      if (previous != null) listen(AnchorMoment.previous, previous),
      if (latest != null && latest != first)
        listen(AnchorMoment.latest, latest),
    ],
    months: [
      for (final MapEntry(key: month, value: row) in byMonth.entries)
        (
          month: month,
          speechRate: number(row, 'speech_rate'),
          longPausesPerMin: number(row, 'long_pauses_per_min'),
          clauses: _speech(row)?.annotation.clauses.length,
          errorFree: _speech(row)?.annotation.clauses
              .where((c) => c.errorFree)
              .length,
        ),
    ],
  );
}
