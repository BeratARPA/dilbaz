import 'dart:async';

import 'package:dilbaz_app/core/audio/clip_player.dart';
import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/repositories/assessment_repository.dart';
import 'package:dilbaz_app/data/repositories/pack_audio.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/repositories/placement_bank.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';

import 'pack_fixture.dart';

/// Vocabulary sizes of the synthetic language's levels: 200 a band.
const List<Map<String, Object?>> zzVocabLevels = [
  {'level': 'A0', 'from': 0, 'to': 200},
  {'level': 'A1', 'from': 200, 'to': 400},
  {'level': 'A2', 'from': 400, 'to': 600},
  {'level': 'B1', 'from': 600, 'to': 800},
  {'level': 'B2', 'from': 800, 'to': 1001},
];

/// A target pack of the synthetic language with a placement test: two
/// versions of a word list (one real word of each band and a made-up one),
/// grammar items at A1 and A2, and dictation sentences for both versions.
Future<BuiltPack> placementPack({
  String id = 'zz@1',
  bool withVocabLevels = true,
}) => buildPack(
  id: id,
  kind: 'target',
  manifest: {
    'min_engine_version': 1,
    'script': {'direction': 'ltr', 'word_separator': 'space'},
    if (withVocabLevels) 'placement': {'vocab_levels': zzVocabLevels},
  },
  normalization: soundNormalization,
  meta: const {
    'audio': {'bucket': 'pack-audio', 'prefix': 'zz/1/'},
  },
  items: [
    for (final version in ['A', 'B']) ...[
      for (var band = 1; band <= 5; band++)
        item(
          'zz.xlex.$version.w$band',
          'xlex',
          packId: id,
          level: '',
          text: 'w$band${version.toLowerCase()}',
          data: {'version': version, 'band': band, 'is_pseudo': false},
        ),
      item(
        'zz.xlex.$version.fake',
        'xlex',
        packId: id,
        level: '',
        text: 'fake${version.toLowerCase()}',
        data: {'version': version, 'band': null, 'is_pseudo': true},
      ),
    ],
    for (final level in ['A1', 'A2'])
      item(
        'zz.pgram.${level.toLowerCase()}.one',
        'placement_grammar',
        packId: id,
        level: level,
        text: 'Bada ___ kolu.',
        data: {
          'answer': 'mi$level',
          'distractors': ['mo', 'mu'],
          'focus': 'a structure',
        },
      ),
    // Out of order, to be sorted by `order`.
    item(
      'zz.pdict.a.2',
      'placement_dictation',
      packId: id,
      level: 'A2',
      text: 'Kolu bada kolu.',
      targets: ['zz.sent.0002'],
      data: {
        'version': 'A',
        'order': 2,
        'audio': [
          {
            'voice': 'v1',
            'speed': 1.0,
            'file': 'v1/two.mp3',
            'duration_ms': 900,
          },
        ],
      },
    ),
    item(
      'zz.pdict.a.1',
      'placement_dictation',
      packId: id,
      text: 'Bada kolu.',
      targets: ['zz.sent.0001'],
      data: {
        'version': 'A',
        'order': 1,
        'audio': [
          {
            'voice': 'v1',
            'speed': 0.8,
            'file': 'v1/slow.mp3',
            'duration_ms': 1200,
          },
          {
            'voice': 'v1',
            'speed': 1.0,
            'file': 'v1/one.mp3',
            'duration_ms': 800,
          },
          {
            'voice': 'v3',
            'speed': 1.0,
            'file': 'v3/one.mp3',
            'duration_ms': 800,
          },
        ],
      },
    ),
    item(
      'zz.pdict.b.1',
      'placement_dictation',
      packId: id,
      text: 'Kolu bada.',
      targets: ['zz.sent.0003'],
      data: {
        'version': 'B',
        'order': 1,
        'audio': [
          {
            'voice': 'v1',
            'speed': 1.0,
            'file': 'v1/three.mp3',
            'duration_ms': 800,
          },
        ],
      },
    ),
  ],
  forms: [
    ContentFormsCompanion.insert(form: 'bada', lemma: 'bada', packId: id),
    ContentFormsCompanion.insert(form: 'kolu', lemma: 'kolu', packId: id),
  ],
);

/// A placement bank made in memory, for controller and widget tests.
PlacementBank zzBank({
  int words = 12,
  bool grammar = true,
  bool dictation = true,
}) => PlacementBank(
  version: 'A',
  words: [
    for (var i = 0; i < words; i++)
      (key: 'zz.xlex.A.$i', word: 'word$i', band: i.isEven ? null : i % 5 + 1),
  ],
  vocabLevels: VocabLevels.fromJson(zzVocabLevels),
  grammar: grammar
      ? {
          for (final level in [CefrLevel.a1, CefrLevel.a2, CefrLevel.b1])
            level: [
              for (var i = 0; i < 12; i++)
                (
                  key: 'zz.pgram.${level.code}.$i',
                  level: level,
                  stem: '${level.code} $i ___.',
                  answer: 'right${level.code}$i',
                  distractors: ['wrong$i', 'other$i'],
                ),
            ],
        }
      : const {},
  dictation: dictation
      ? const [
          (
            key: 'zz.pdict.a.1',
            level: CefrLevel.a1,
            text: 'Bada kolu.',
            clip: 'zz/1/v1/one.mp3',
          ),
          (
            key: 'zz.pdict.a.2',
            level: CefrLevel.a2,
            text: 'Kolu bada kolu.',
            clip: 'zz/1/v1/two.mp3',
          ),
        ]
      : const [],
  language: PackLanguage(
    rules: NormalizationRules.fromJson(soundNormalization),
    forms: const {
      'bada': {'bada'},
      'kolu': {'kolu'},
    },
  ),
);

/// Clips that are always there, or never.
class FakePackAudio implements PackAudio {
  /// Why the next clips cannot be fetched; null means they can.
  PackFailure? failure;
  final fetched = <String>[];

  @override
  Future<Result<String, PackFailure>> file(String clip) async {
    fetched.add(clip);
    final failure = this.failure;
    return failure == null ? Ok('/clips/$clip') : Err(failure);
  }
}

/// A player that plays at once, or waits for [release].
class FakeClipPlayer implements ClipPlayer {
  final played = <String>[];
  int stops = 0;
  bool disposed = false;

  /// While set, a clip plays until it completes.
  Completer<void>? release;

  /// Whether the next clips play.
  bool works = true;

  @override
  Future<bool> play(String path) async {
    played.add(path);
    await release?.future;
    return works;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposed = true;
}

/// Hands out a bank made in memory; null means no test on the device.
class FakeBankRepository implements PlacementBankRepository {
  new(this.bank);

  final PlacementBank? bank;
  final taken = <int>[];

  @override
  Future<PlacementBank?> load({required String l2, required int taken}) async {
    this.taken.add(taken);
    return bank;
  }

  @override
  Stream<bool> watchAvailable(String l2) => Stream.value(bank != null);
}

/// A course in memory and the placement tests saved for it.
class FakeAssessmentRepository implements AssessmentRepository {
  new({this.studied = zzCourse, this._open = true});

  static const StudiedCourse zzCourse = (
    id: 'course-1',
    l2: 'zz',
    level: CefrLevel.a2,
  );

  StudiedCourse? studied;
  bool _open;
  final _changes = StreamController<bool>.broadcast();
  final saved = <PlacementOutcome>[];

  @override
  Future<StudiedCourse?> course(String userId) async => studied;

  @override
  Future<int> placementsTaken(String courseId) async => saved.length;

  /// The vocabulary result of the latest test; none unless set.
  XlexResult? xlex;

  @override
  Future<XlexResult?> latestXlex(String courseId) async => xlex;

  @override
  Stream<bool> watchPlacementOpen(String userId) async* {
    yield _open;
    yield* _changes.stream;
  }

  @override
  Future<void> savePlacement({
    required String userId,
    required String courseId,
    required Map<String, Object?> results,
    required PlacementOutcome outcome,
    int? vocabulary,
  }) async {
    saved.add(outcome);
    _open = false;
    _changes.add(false);
  }
}
