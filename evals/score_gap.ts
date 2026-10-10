/**
 * Scores of a gap_suggest eval run (docs/07-ai-tutor.md §8).
 *
 * There is no single right English for what a learner could not say, so the
 * run is scored on what can be checked: the level of `l2_simple` at A
 * levels (at most one word above the learner's level plus one in each
 * sentence), a key chunk copied from the answer, short notes, and calls
 * that work. Meaning is read by a person against the case's reference.
 */
import type { CallResult } from "./score.ts";

/** A model's answer to one case, after the route's level check. */
export interface GapCaseResult {
  id: string;
  model: string;
  prompt: string;
  level: string;
  /** The route's failure code when no valid answer came. */
  code?: string;
  l2_natural?: string;
  l2_simple?: string;
  key_chunk?: { text: string; gloss_l1: string };
  notes_l1?: string | null;
  /** Words above the level in each sentence of `l2_simple` (A levels). */
  above?: string[][];
  simplified?: boolean;
  calls: CallResult[];
}

/** docs/07 §8: the share of A-level answers within the rule. */
export const gapThresholds = { levelOk: 0.95 };

export interface GapScore {
  model: string;
  cases: number;
  failures: number;
  /** A-level answers whose every sentence keeps ≤ 1 word above the level. */
  levelChecked: number;
  levelOk: number;
  simplified: number;
  /** The key chunk is copied from l2_natural or l2_simple. */
  chunkCopied: number;
  /** Notes over 20 words at A levels. */
  longNotes: number;
  /** First calls whose answer passed the schema. */
  schemaValid: number;
  latencyP50: number;
  latencyP90: number;
  tokensPerCase: number;
  passes: { levelOk: boolean };
}

const isA = (level: string) => ["A0", "A1", "A2"].includes(level);

function percentile(values: number[], share: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(share * sorted.length))];
}

export function scoreGap(model: string, results: GapCaseResult[]): GapScore {
  const answered = results.filter((r) => r.code === undefined);
  const checked = answered.filter((r) => isA(r.level));
  const levelOk =
    checked.filter((r) => (r.above ?? []).every((words) => words.length <= 1))
      .length;
  const share = (count: number, of: number) => of === 0 ? 1 : count / of;
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
  const levelShare = share(levelOk, checked.length);
  return {
    model,
    cases: results.length,
    failures: results.length - answered.length,
    levelChecked: checked.length,
    levelOk: levelShare,
    simplified: answered.filter((r) => r.simplified).length,
    chunkCopied: share(
      answered.filter((r) => {
        const chunk = r.key_chunk?.text.toLowerCase() ?? "";
        return chunk !== "" &&
          ((r.l2_natural ?? "").toLowerCase().includes(chunk) ||
            (r.l2_simple ?? "").toLowerCase().includes(chunk));
      }).length,
      answered.length,
    ),
    longNotes: answered.filter((r) =>
      isA(r.level) &&
      (r.notes_l1 ?? "").split(/\s+/).filter(Boolean).length > 20
    ).length,
    schemaValid: share(
      results.filter((r) => r.calls[0]?.stopReason === "stop").length,
      results.length,
    ),
    latencyP50: percentile(latencies, 0.5),
    latencyP90: percentile(latencies, 0.9),
    tokensPerCase: results.length === 0
      ? 0
      : Math.round(tokens.reduce((a, b) => a + b, 0) / results.length),
    passes: { levelOk: levelShare >= gapThresholds.levelOk },
  };
}
