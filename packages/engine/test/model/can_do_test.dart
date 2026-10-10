import 'package:dilbaz_engine/dilbaz_engine.dart';
import 'package:test/test.dart';

final DateTime now = DateTime.utc(2026, 10);

CanDoAttempt attempt(
  int daysAgo, {
  String code = 'cd.x.a2',
  String prompt = 'zz.task.home',
  TaskOutcome outcome = TaskOutcome.done,
  bool scaffolded = true,
}) => (
  code: code,
  day: now.subtract(Duration(days: daysAgo)),
  prompt: prompt,
  outcome: outcome,
  scaffolded: scaffolded,
);

void main() {
  test('attempted, then shown, then established (docs/04 §5)', () {
    expect(
      canDoEvidence([attempt(1, outcome: TaskOutcome.partial)], now: now),
      {'cd.x.a2': (status: CanDoStatus.attempted, refresh: false)},
    );
    expect(
      canDoEvidence([attempt(1)], now: now)['cd.x.a2']!.status,
      CanDoStatus.shown,
    );
    // Two days, but the same prompt: shown.
    expect(
      canDoEvidence([attempt(1), attempt(3)], now: now)['cd.x.a2']!.status,
      CanDoStatus.shown,
    );
    // Different prompts on one day: shown.
    expect(
      canDoEvidence([
        attempt(1),
        attempt(1, prompt: 'zz.task.city'),
      ], now: now)['cd.x.a2']!.status,
      CanDoStatus.shown,
    );
    expect(
      canDoEvidence([
        attempt(1),
        attempt(3, prompt: 'zz.task.city'),
      ], now: now)['cd.x.a2']!.status,
      CanDoStatus.established,
    );
  });

  test('established needs a recent done; an old one invites a refresh', () {
    final old = [attempt(70), attempt(75, prompt: 'zz.task.city')];
    expect(canDoEvidence(old, now: now)['cd.x.a2'], (
      status: CanDoStatus.shown,
      refresh: false,
    ));
    final older = [attempt(130), attempt(140, prompt: 'zz.task.city')];
    expect(canDoEvidence(older, now: now)['cd.x.a2'], (
      status: CanDoStatus.shown,
      refresh: true,
    ));
  });

  test('from B1 one done must be without scaffolds', () {
    final scaffolded = [
      attempt(1, code: 'cd.y.b1'),
      attempt(3, code: 'cd.y.b1', prompt: 'zz.task.city'),
    ];
    const levels = {'cd.y.b1': CefrLevel.b1};
    expect(
      canDoEvidence(scaffolded, now: now, levels: levels)['cd.y.b1']!.status,
      CanDoStatus.shown,
    );
    expect(
      canDoEvidence(
        [...scaffolded, attempt(5, code: 'cd.y.b1', scaffolded: false)],
        now: now,
        levels: levels,
      )['cd.y.b1']!.status,
      CanDoStatus.established,
    );
    expect(canDoEvidence(const [], now: now), isEmpty);
  });
}
