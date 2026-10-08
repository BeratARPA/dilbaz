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
