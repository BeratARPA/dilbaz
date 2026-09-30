/**
 * Scores of an answer_check eval run (docs/07-ai-tutor.md §8).
 *
 * One `CaseResult` per case and model; `score` turns a model's results into
 * the metrics and checks them against the thresholds of docs/07 §8.
 */

/** What the gold set says about a case (`cases.jsonl`, `expected`). */
export interface Expected {
  verdicts: string[];
  target_ok: boolean | null;
  tags: string[];
}

/** One call of the case, as `llm_usage` would record it. */
export interface CallResult {
  stopReason: string;
  latencyMs: number;
  inputTokens: number | null;
  outputTokens: number | null;
  cachedTokens: number | null;
}

/** A model's answer to one case, after the route's guards. */
export interface CaseResult {
  id: string;
  model: string;
  prompt: string;
  level: string;
  expected: Expected;
  /** The route's failure code when no valid answer came. */
  code?: string;
  verdict?: string;
  target_ok?: boolean;
  error_tags?: string[];
  ladder?: { h1: string; h2: string; h3: string; h4: string };
  /** Hints the leak check blanked (the model gave the answer away). */
  leaked?: string[];
  /** Served hints that still give the answer away, checked again. */
  servedLeaks?: number;
  calls: CallResult[];
}

export interface Thresholds {
  accuracy: number;
  falseWrong: number;
  leakServed: number;
  schemaValid: number;
}

/** docs/07 §8, answer_check. */
export const answerCheckThresholds: Thresholds = {
  accuracy: 0.9,
  falseWrong: 0.03,
  leakServed: 0,
  schemaValid: 1,
};

export interface Score {
  model: string;
  cases: number;
  /** Cases without a valid answer after the retries. */
  failures: number;
  /** Verdict among the gold set's verdicts; a failure counts as a miss. */
  accuracy: number;
  /** Correct or acceptable answers judged a miss for the card. */
  falseWrong: number;
  goldCorrect: number;
  /** target_ok as the gold set has it, where it has one. */
  targetOk: number;
  /** Tagged errors that carry one of the expected tags. */
  tagHit: number;
  /** First answers that passed the contract (JSON, schema, closed tags). */
  schemaValid: number;
  /** Hints served that give the answer away: 0 by the route's guard. */
  leakServed: number;
  /** Hints the model wrote that gave the answer away (blanked). */
  leakRaw: number;
  /** A-level hints longer than 20 words. */
  longHints: number;
  latencyP50: number;
  latencyP95: number;
  tokens: { input: number; cached: number; output: number };
  passes: Record<keyof Thresholds, boolean>;
}

const correctVerdicts = new Set(["correct", "acceptable_variant"]);
const hintKeys = ["h1", "h2", "h3"] as const;

/** A gold-correct case: every accepted verdict is a correct one. */
export function isGoldCorrect(expected: Expected): boolean {
  return expected.verdicts.every((v) => correctVerdicts.has(v));
}

/** The answer counts as a miss for the card (docs/03 §0.2). */
export function calledWrong(result: CaseResult): boolean {
  if (result.verdict === undefined) return false;
  return result.verdict === "wrong" || result.verdict === "off_target" ||
    (result.verdict === "minor_error" && result.target_ok === false);
}

function ratio(part: number, whole: number): number {
  return whole === 0 ? 0 : part / whole;
}

function percentile(values: number[], p: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
}

const words = (text: string) => text.split(/\s+/).filter((w) => w !== "");

export function score(
  model: string,
  results: CaseResult[],
  thresholds: Thresholds = answerCheckThresholds,
): Score {
  const answered = results.filter((r) => r.verdict !== undefined);
  const right = answered.filter((r) =>
    r.expected.verdicts.includes(r.verdict!)
  );
  const gold = results.filter((r) => isGoldCorrect(r.expected));
  const withTarget = answered.filter((r) => r.expected.target_ok !== null);
  const tagged = answered.filter((r) =>
    r.expected.tags.length > 0 && (r.error_tags ?? []).length > 0
  );
  const firsts = results
    .map((r) => r.calls[0]?.stopReason)
    .filter((s) => s === "stop" || s === "invalid");
  const served = answered.flatMap((r) =>
    hintKeys.map((k) => r.ladder?.[k] ?? "").filter((h) => h !== "")
  );
  const rawHints = served.length +
    answered.reduce((n, r) => n + (r.leaked?.length ?? 0), 0);
  const aLevel = answered.filter((r) => r.level.startsWith("A"));
  const latencies = results.flatMap((r) =>
    r.calls.filter((c) => c.stopReason === "stop").map((c) => c.latencyMs)
  );
  const calls = results.flatMap((r) => r.calls);
  const sum = (pick: (c: CallResult) => number | null) =>
    calls.reduce((n, c) => n + (pick(c) ?? 0), 0);

  const accuracy = ratio(right.length, results.length);
  const falseWrong = ratio(gold.filter(calledWrong).length, gold.length);
  const schemaValid = ratio(
    firsts.filter((s) => s === "stop").length,
    firsts.length,
  );
  const leakServed = ratio(
    answered.reduce((n, r) => n + (r.servedLeaks ?? 0), 0),
    served.length,
  );
  return {
    model,
    cases: results.length,
    failures: results.length - answered.length,
    accuracy,
    falseWrong,
    goldCorrect: gold.length,
    targetOk: ratio(
      withTarget.filter((r) => r.target_ok === r.expected.target_ok).length,
      withTarget.length,
    ),
    tagHit: ratio(
      tagged.filter((r) =>
        r.expected.tags.some((t) => r.error_tags!.includes(t))
      )
        .length,
      tagged.length,
    ),
    schemaValid,
    leakServed,
    leakRaw: ratio(rawHints - served.length, rawHints),
    longHints: aLevel.reduce(
      (n, r) =>
        n +
        hintKeys.filter((k) => words(r.ladder?.[k] ?? "").length > 20).length,
      0,
    ),
    latencyP50: percentile(latencies, 0.5),
    latencyP95: percentile(latencies, 0.95),
    tokens: {
      input: sum((c) => c.inputTokens),
      cached: sum((c) => c.cachedTokens),
      output: sum((c) => c.outputTokens),
    },
    passes: {
      accuracy: accuracy >= thresholds.accuracy,
      falseWrong: falseWrong <= thresholds.falseWrong,
      leakServed: leakServed <= thresholds.leakServed,
      schemaValid: schemaValid >= thresholds.schemaValid,
    },
  };
}
