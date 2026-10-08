/**
 * Scores of a speaking_annotate eval run (docs/07-ai-tutor.md §8).
 *
 * - Error detection F1: a marked error counts when it overlaps a gold
 *   error's words (each gold error is matched once); the tag is scored
 *   apart, among the matched.
 * - EFC: the absolute difference between the route's error-free clause
 *   ratio and the gold one, its median over the cases.
 * - Task outcome agreement.
 * A failed call misses every gold error and the outcome.
 */
import type { CallResult } from "./score.ts";
import type { SpeakingExpected } from "./speaking_cases.ts";

type Span = { start_i: number; end_i: number; tag: string };

/** A model's marks for one case, after the route's guards. */
export interface SpeakingCaseResult {
  id: string;
  model: string;
  prompt: string;
  level: string;
  expected: SpeakingExpected;
  /** The route's failure code when no valid answer came. */
  code?: string;
  errors?: Span[];
  clauses?: number;
  efc?: number | null;
  outcome?: string;
  /** Hints blanked by the leak check. */
  leaked?: string[];
  calls: CallResult[];
}

/** docs/07 §8. */
export const speakingThresholds = {
  errorF1: 0.75,
  efcMedianDiff: 0.10,
  outcomeAgreement: 0.85,
};

export interface SpeakingScore {
  model: string;
  cases: number;
  failures: number;
  errorPrecision: number;
  errorRecall: number;
  errorF1: number;
  /** Matched errors with the gold tag. */
  tagAgreement: number;
  efcMedianDiff: number;
  outcomeAgreement: number;
  leakedHints: number;
  schemaValid: number;
  latencyP50: number;
  latencyP90: number;
  tokensPerCase: number;
  passes: { errorF1: boolean; efc: boolean; outcome: boolean };
}

const overlaps = (a: Span, b: Span) =>
  a.start_i <= b.end_i && b.start_i <= a.end_i;

/** Gold errors found, and of them those with the gold tag. */
export function matchErrors(
  gold: readonly Span[],
  marked: readonly Span[],
): { matched: number; sameTag: number } {
  const taken = new Set<number>();
  let matched = 0;
  let sameTag = 0;
  for (const mark of marked) {
    const found = gold.findIndex((g, i) => !taken.has(i) && overlaps(g, mark));
    if (found < 0) continue;
    taken.add(found);
    matched++;
    if (gold[found].tag === mark.tag) sameTag++;
  }
  return { matched, sameTag };
}

function percentile(values: number[], share: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(share * sorted.length))];
}

function median(values: number[]): number {
  if (values.length === 0) return 1;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
}

export function scoreSpeaking(
  model: string,
  results: SpeakingCaseResult[],
  thresholds = speakingThresholds,
): SpeakingScore {
  let gold = 0;
  let marked = 0;
  let matched = 0;
  let sameTag = 0;
  const efcDiffs: number[] = [];
  let agreed = 0;
  for (const result of results) {
    gold += result.expected.errors.length;
    if (result.code !== undefined) continue;
    const errors = result.errors ?? [];
    marked += errors.length;
    const found = matchErrors(result.expected.errors, errors);
    matched += found.matched;
    sameTag += found.sameTag;
    efcDiffs.push(
      result.efc === null || result.efc === undefined
        ? 1
        : Math.abs(result.efc - result.expected.efc),
    );
    if (result.outcome === result.expected.outcome) agreed++;
  }
  const share = (part: number, whole: number) => whole === 0 ? 1 : part / whole;
  const precision = share(matched, marked);
  const recall = share(matched, gold);
  const f1 = precision + recall === 0
    ? 0
    : 2 * precision * recall / (precision + recall);
  // A failed call is the largest difference.
  const failures = results.filter((r) => r.code !== undefined).length;
  const diffs = [...efcDiffs, ...Array<number>(failures).fill(1)];
  const efcMedian = median(diffs);
  const outcome = share(agreed, results.length);
  const latencies = results.map((r) =>
    r.calls.reduce((sum, call) => sum + call.latencyMs, 0)
  );
  const tokens = results.map((r) =>
    r.calls.reduce(
      (sum, call) =>
        sum + (call.inputTokens ?? 0) - (call.cachedTokens ?? 0) +
        (call.outputTokens ?? 0),
      0,
    )
  );
  return {
    model,
    cases: results.length,
    failures,
    errorPrecision: precision,
    errorRecall: recall,
    errorF1: f1,
    tagAgreement: share(sameTag, matched),
    efcMedianDiff: efcMedian,
    outcomeAgreement: outcome,
    leakedHints: results.reduce((sum, r) => sum + (r.leaked?.length ?? 0), 0),
    schemaValid: share(
      results.filter((r) => r.calls[0]?.stopReason === "stop").length,
      results.length,
    ),
    latencyP50: percentile(latencies, 0.5),
    latencyP90: percentile(latencies, 0.9),
    tokensPerCase: results.length === 0
      ? 0
      : Math.round(tokens.reduce((a, b) => a + b, 0) / results.length),
    passes: {
      errorF1: f1 >= thresholds.errorF1,
      efc: efcMedian <= thresholds.efcMedianDiff,
      outcome: outcome >= thresholds.outcomeAgreement,
    },
  };
}
