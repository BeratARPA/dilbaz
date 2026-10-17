import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

void main() {
  group('InfoGapCheck (A15)', () {
    const choose = ChooseKey(chooser: 'b', option: 'c');

    test('a choice: right, wrong, or none yet', () {
      final right = InfoGapCheck.of(choose, {'a': 'done', 'b': 'c'});
      expect((right.found, right.total, right.wrong), (1, 1, 0));
      expect(right.solved, isTrue);
      expect(right.outcome, TaskOutcome.done);
      final wrong = InfoGapCheck.of(choose, {'a': 'done', 'b': 'a'});
      expect(
        (wrong.solved, wrong.wrong, wrong.outcome),
        (false, 1, TaskOutcome.notDone),
      );
      expect(InfoGapCheck.of(choose, {}).wrong, 0);
    });

    const differences = DifferencesKey(a: [0, 2, 5], b: [1, 2, 4]);

    test('differences: found by either partner, wrong marks counted', () {
      final all = InfoGapCheck.of(differences, {
        'a': [0, 2],
        'b': [4],
      });
      expect((all.found, all.total, all.wrong), (3, 3, 0));
      expect(all.outcome, TaskOutcome.done);

      final some = InfoGapCheck.of(differences, {
        'a': [0, 3],
        'b': <Object?>['x'],
      });
      expect((some.found, some.wrong, some.solved), (1, 1, false));
      expect(some.outcome, TaskOutcome.partial);

      final none = InfoGapCheck.of(differences, {'a': 'oops'});
      expect((none.found, none.outcome), (0, TaskOutcome.notDone));
    });
  });
}
