/**
 * Scores of the pron_check eval (ADR-0011, docs/07-ai-tutor.md §8).
 *
 * A wrong alarm teaches a mistake the learner did not make, so the first
 * measure is how often a sentence said right gets a problem; then how often
 * a mistake is found on its word with its tag.
 */

/** A case: the sentence, and the mistake put on word i, if any. */
export interface PronCase {
  id: string;
  text: string;
  i: number;
  expect: { i: number; tag: string } | null;
}

/** What the route answered for one case, or why it did not. */
export interface PronResult {
  id: string;
  model: string;
  failure?: string;
  uncertain?: boolean;
  issues?: { i: number; tag: string; heard: string }[];
  latencyMs?: number;
}

/** ADR-0011: wrong alarms on right sentences ≤ 10 %, mistakes found ≥ 60 %. */
export const pronThresholds = { falseAlarm: 0.1, found: 0.6 };

export interface PronScore {
  model: string;
  answered: number;
  failed: number;
  /** Sentences said right that got a problem. */
  falseAlarm: number;
  /** Mistakes found on their word with their tag. */
  found: number;
  /** Mistakes found on their word, with any tag. */
  onWord: number;
  /** Problems on other words of a sentence with a mistake, per sentence. */
  strayPerCase: number;
  uncertain: number;
  /** Found rate by tag. */
  byTag: Record<string, number>;
  medianLatencyMs: number | null;
  passes: boolean;
}

const rate = (part: number, whole: number) =>
  whole === 0 ? 0 : Math.round((part / whole) * 1000) / 1000;

export function scorePron(cases: PronCase[], results: PronResult[]): PronScore {
  const byId = new Map(cases.map((c) => [c.id, c]));
  const answered = results.filter((r) => !r.failure && byId.has(r.id));
  const clean = answered.filter((r) => byId.get(r.id)!.expect === null);
  const wrong = answered.filter((r) => byId.get(r.id)!.expect !== null);
  const issues = (r: PronResult) => r.uncertain ? [] : r.issues ?? [];
  const hit = (r: PronResult) => {
    const expect = byId.get(r.id)!.expect!;
    return issues(r).some((x) => x.i === expect.i && x.tag === expect.tag);
  };
  const tags = new Map<string, [number, number]>();
  for (const r of wrong) {
    const tag = byId.get(r.id)!.expect!.tag;
    const [found, all] = tags.get(tag) ?? [0, 0];
    tags.set(tag, [found + (hit(r) ? 1 : 0), all + 1]);
  }
  const latencies = answered
    .map((r) => r.latencyMs)
    .filter((ms): ms is number => ms !== undefined)
    .sort((a, b) => a - b);
  const falseAlarm = rate(
    clean.filter((r) => issues(r).length > 0).length,
    clean.length,
  );
  const found = rate(wrong.filter(hit).length, wrong.length);
  return {
    model: results[0]?.model ?? "",
    answered: answered.length,
    failed: results.length - answered.length,
    falseAlarm,
    found,
    onWord: rate(
      wrong.filter((r) =>
        issues(r).some((x) => x.i === byId.get(r.id)!.expect!.i)
      ).length,
      wrong.length,
    ),
    strayPerCase: rate(
      wrong.reduce(
        (sum, r) =>
          sum +
          issues(r).filter((x) => x.i !== byId.get(r.id)!.expect!.i).length,
        0,
      ),
      wrong.length,
    ),
    uncertain: rate(
      answered.filter((r) => r.uncertain).length,
      answered.length,
    ),
    byTag: Object.fromEntries(
      [...tags].map(([tag, [hits, all]]) => [tag, rate(hits, all)]),
    ),
    medianLatencyMs: latencies.length === 0
      ? null
      : latencies[Math.floor(latencies.length / 2)],
    passes: clean.length > 0 && wrong.length > 0 &&
      falseAlarm <= pronThresholds.falseAlarm &&
      found >= pronThresholds.found,
  };
}
