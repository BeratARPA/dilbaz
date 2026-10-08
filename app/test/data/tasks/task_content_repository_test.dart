import 'package:dilbaz_app/core/result.dart';
import 'package:dilbaz_app/data/db/app_database.dart';
import 'package:dilbaz_app/data/db/pack_importer.dart';
import 'package:dilbaz_app/data/repositories/pack_remote.dart';
import 'package:dilbaz_app/data/tasks/speaking_task.dart';
import 'package:dilbaz_app/data/tasks/task_content_repository.dart';
import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pack_fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  ContentTasksCompanion task(
    String key, {
    String kind = 'speaking',
    String level = 'A1',
    Map<String, Object?> data = const {},
  }) => ContentTasksCompanion.insert(
    key: key,
    packId: 'zz@1',
    kind: kind,
    level: level,
    data: Value({'goal': 'Tell about $key.', ...data}),
  );

  ContentPairEntriesCompanion instruction(
    String key, {
    List<String>? phrases,
  }) => ContentPairEntriesCompanion.insert(
    kind: 'task_instruction',
    key: key,
    packId: 'qq-zz@1',
    data: {
      'title': 'Başlık $key',
      'prompt': 'Anlat: $key.',
      'phrases': ?phrases,
    },
  );

  Future<void> install({
    List<ContentTasksCompanion> tasks = const [],
    List<ContentPairEntriesCompanion> instructions = const [],
    Map<String, Object?> meta = const {},
  }) async {
    for (final built in [
      await buildPack(
        id: 'zz@1',
        kind: 'target',
        manifest: {'min_engine_version': 1},
        normalization: soundNormalization,
        tasks: tasks,
        meta: meta,
      ),
      await buildPack(
        id: 'qq-zz@1',
        kind: 'pair',
        l1: 'qq',
        pairEntries: instructions,
      ),
    ]) {
      final result = await PackImporter(db).import(built.bytes, built.info);
      expect(result, isA<Ok<void, PackFailure>>(), reason: built.info.id);
    }
  }

  test('speaking tasks come with what the learner reads', () async {
    await install(
      tasks: [
        task(
          'zz.task.anc_1',
          data: {
            'anchor': 'ANC-1',
            'can_do': ['cd.x.a1'],
            'phrases': <String>[],
          },
        ),
        task(
          'zz.task.home',
          level: 'A2',
          data: {
            'can_do': ['cd.x.a2'],
            'phrases': ['Bada ...', 'Kolu ...'],
          },
        ),
      ],
      instructions: [
        instruction('zz.task.anc_1'),
        instruction('zz.task.home', phrases: ['Bada demek ...', 'Kolu ...']),
      ],
    );

    final tasks = await DriftTaskContentRepository(
      db,
      l2: 'zz',
    ).speakingTasks();

    expect(tasks, [
      const SpeakingTask(
        key: 'zz.task.anc_1',
        level: CefrLevel.a1,
        goal: 'Tell about zz.task.anc_1.',
        title: 'Başlık zz.task.anc_1',
        prompt: 'Anlat: zz.task.anc_1.',
        anchor: 'ANC-1',
        canDo: ['cd.x.a1'],
      ),
      const SpeakingTask(
        key: 'zz.task.home',
        level: CefrLevel.a2,
        goal: 'Tell about zz.task.home.',
        title: 'Başlık zz.task.home',
        prompt: 'Anlat: zz.task.home.',
        canDo: ['cd.x.a2'],
        phrases: ['Bada ...', 'Kolu ...'],
        phraseMeanings: ['Bada demek ...', 'Kolu ...'],
      ),
    ]);
  });

  test('a task without its instruction, level or kind is left out', () async {
    await install(
      tasks: [
        task('zz.task.alone'),
        task('zz.task.odd', level: 'Z9'),
        task('zz.task.role', kind: 'role_play'),
        task('zz.task.ok'),
      ],
      instructions: [
        instruction('zz.task.odd'),
        instruction('zz.task.role'),
        instruction('zz.task.ok'),
      ],
    );
    final tasks = await DriftTaskContentRepository(
      db,
      l2: 'zz',
    ).speakingTasks();
    expect(tasks.map((t) => t.key), ['zz.task.ok']);
  });

  test("connectors come from the target pack's settings", () async {
    final repository = DriftTaskContentRepository(db, l2: 'zz');
    expect(await repository.connectors(), isEmpty);
    await install(
      meta: {
        'connectors': [
          {'text': 'kolu', 'level': 'A1'},
          {'text': 'sima dero', 'level': 'A2'},
          {'level': 'B1'},
        ],
      },
    );
    expect(await repository.connectors(), ['kolu', 'sima dero']);
  });
}
