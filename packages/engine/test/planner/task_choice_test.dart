import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

const List<TaskCandidate> tasks = [
  (key: 'zz.task.a1_1', level: CefrLevel.a1),
  (key: 'zz.task.a1_2', level: CefrLevel.a1),
  (key: 'zz.task.a2_1', level: CefrLevel.a2),
  (key: 'zz.task.a2_2', level: CefrLevel.a2),
  (key: 'zz.task.b1_1', level: CefrLevel.b1),
];

void main() {
  monthlyTests();
  test("the learner's level first, then lower ones; none above", () {
    final keys = suggestTasks(tasks: tasks, level: CefrLevel.a2, seed: 7);
    expect(keys.take(2).toSet(), {'zz.task.a2_1', 'zz.task.a2_2'});
    expect(keys.skip(2).toSet(), {'zz.task.a1_1', 'zz.task.a1_2'});
  });

  test('below A1 the A1 tasks are offered', () {
    expect(suggestTasks(tasks: tasks, level: CefrLevel.a0, seed: 7).toSet(), {
      'zz.task.a1_1',
      'zz.task.a1_2',
    });
  });

  test('a task done lately goes last', () {
    final keys = suggestTasks(
      tasks: tasks,
      level: CefrLevel.a2,
      seed: 7,
      doneLately: {'zz.task.a2_1', 'zz.task.a2_2'},
    );
    expect(keys.take(2).toSet(), {'zz.task.a1_1', 'zz.task.a1_2'});
    expect(keys.skip(2).toSet(), {'zz.task.a2_1', 'zz.task.a2_2'});
  });

  test('the same seed gives the same order, whatever the input order', () {
    final once = suggestTasks(tasks: tasks, level: CefrLevel.b1, seed: 3);
    final again = suggestTasks(
      tasks: tasks.reversed,
      level: CefrLevel.b1,
      seed: 3,
    );
    expect(again, once);
    expect(once.first, 'zz.task.b1_1');
    final orders = {
      for (var seed = 0; seed < 20; seed++)
        suggestTasks(tasks: tasks, level: CefrLevel.a1, seed: seed).join(),
    };
    expect(orders.length, greaterThan(1));
  });
}

const List<TestTask> testTasks = [
  (key: 'zz.task.anc_2', level: CefrLevel.a1, anchor: 'ANC-2'),
  (key: 'zz.task.anc_10', level: CefrLevel.a1, anchor: 'ANC-10'),
  (key: 'zz.task.anc_1', level: CefrLevel.a1, anchor: 'ANC-1'),
  (key: 'zz.task.a1_1', level: CefrLevel.a1, anchor: null),
  (key: 'zz.task.a2_1', level: CefrLevel.a2, anchor: null),
  (key: 'zz.task.a2_2', level: CefrLevel.a2, anchor: null),
  (key: 'zz.task.a2_3', level: CefrLevel.a2, anchor: null),
];

void monthlyTests() {
  test('the anchors in order, then two tasks of the level by turns', () {
    final october = monthlyTasks(
      tasks: testTasks,
      level: CefrLevel.a2,
      month: 2026 * 12 + 9,
    );
    expect(october.take(3), [
      'zz.task.anc_1',
      'zz.task.anc_2',
      'zz.task.anc_10',
    ]);
    expect(october.skip(3), hasLength(2));
    final november = monthlyTasks(
      tasks: testTasks,
      level: CefrLevel.a2,
      month: 2026 * 12 + 10,
    );
    expect(november.take(3), october.take(3));
    // The level tasks move on, wrapping round.
    expect(november.skip(3), isNot(october.skip(3)));
    expect(
      {...october.skip(3), ...november.skip(3)},
      {'zz.task.a2_1', 'zz.task.a2_2', 'zz.task.a2_3'},
    );
  });

  test('below A1 and above the packs, the nearest level that has tasks', () {
    expect(
      monthlyTasks(tasks: testTasks, level: CefrLevel.a0, month: 5).skip(3),
      ['zz.task.a1_1'],
    );
    expect(
      monthlyTasks(tasks: testTasks, level: CefrLevel.b2, month: 0).skip(3),
      ['zz.task.a2_1', 'zz.task.a2_2'],
    );
    expect(
      monthlyTasks(
        tasks: [
          for (final t in testTasks)
            if (t.anchor != null) t,
        ],
        level: CefrLevel.b1,
        month: 0,
      ),
      hasLength(3),
    );
  });
}
