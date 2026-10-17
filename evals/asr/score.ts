/**
 * Scores of the ASR bake-off (docs/08-speech.md §3.2).
 *
 * The first measure is error keeping: a learner's error must reach the
 * transcript as said, not corrected. Then word error rate against the
 * verbatim reference, filler capture on free speech, and latency.
 */

/** A scripted item: what was read, the error to keep, its correction. */
export interface ScriptedItem {
  id: string;
  text: string;
  keep: string[];
  fix: string[];
}

/** One recognizer's answer to one recording. */
export interface AsrResult {
  id: string;
  candidate: string;
  /** The failure when no transcript came. */
  failure?: string;
  text?: string;
  latencyMs?: number;
}

/** docs/08 §3.2: errors kept as said. */
export const asrThresholds = { errorKept: 0.9 };

/** Spoken hesitations a verbatim transcript keeps. */
export const fillers = new Set([
  "uh",
  "um",
  "uhm",
  "umm",
  "er",
  "erm",
  "eh",
  "ah",
  "hmm",
  "mm",
  "ee",
  "eee",
]);

/** Lowercase words without punctuation; "didn't" stays one word. */
export function words(text: string): string[] {
  return text
    .toLowerCase()
    .replaceAll(/[’‘`]/g, "'")
    .replaceAll(/[^a-z0-9' ]+/g, " ")
    .split(/\s+/)
    .map((word) => word.replaceAll(/^'+|'+$/g, ""))
    .filter((word) => word !== "");
}

/** Whether [phrase]'s words come in [text] one after the other. */
export function says(text: string, phrase: string): boolean {
  const hay = ` ${words(text).join(" ")} `;
  return hay.includes(` ${words(phrase).join(" ")} `);
}

/** The error reached the transcript as said, and no correction did. */
export function keepsError(item: ScriptedItem, transcript: string): boolean {
  return item.keep.every((phrase) => says(transcript, phrase)) &&
    !item.fix.some((phrase) => says(transcript, phrase));
}

/** Word error rate: edits to turn the reference into the hypothesis. */
export function wer(reference: string, hypothesis: string): number {
  const ref = words(reference);
  const hyp = words(hypothesis);
  if (ref.length === 0) return hyp.length === 0 ? 0 : 1;
  let previous = Array.from({ length: hyp.length + 1 }, (_, j) => j);
  for (let i = 1; i <= ref.length; i++) {
    const current = [i];
    for (let j = 1; j <= hyp.length; j++) {
      const swap = previous[j - 1] + (ref[i - 1] === hyp[j - 1] ? 0 : 1);
      current[j] = Math.min(swap, previous[j] + 1, current[j - 1] + 1);
    }
    previous = current;
  }
  return previous[hyp.length] / ref.length;
}

/** Fillers of [text], in order. */
export function fillersOf(text: string): string[] {
  return words(text).filter((word) => fillers.has(word));
}

function percentile(values: number[], p: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
}

export interface AsrScore {
  candidate: string;
  scripted: number;
  failures: number;
  /** Share of scripted items whose error was kept as said. */
  errorKept: number;
  /** Ids whose error was corrected or lost. */
  errorLost: string[];
  /** Mean WER on scripted items, against the text read. */
  werScripted: number;
  /** Mean WER on free items with a reference; null without any. */
  werFree: number | null;
  /** Share of the reference's fillers found in the transcript. */
  fillerCapture: number | null;
  latencyP50: number | null;
  latencyP90: number | null;
  passes: { errorKept: boolean };
}

/** The candidate's scores; [references] are the free items' verbatim text. */
export function scoreAsr(
  candidate: string,
  items: ScriptedItem[],
  results: AsrResult[],
  references: Map<string, string> = new Map(),
): AsrScore {
  const byId = new Map(results.map((result) => [result.id, result]));
  const lost: string[] = [];
  const werScripted: number[] = [];
  let failures = 0;
  let kept = 0;
  for (const item of items) {
    const text = byId.get(item.id)?.text;
    if (text === undefined) {
      failures++;
      lost.push(item.id);
      werScripted.push(1);
      continue;
    }
    if (keepsError(item, text)) kept++;
    else lost.push(item.id);
    werScripted.push(wer(item.text, text));
  }
  const werFree: number[] = [];
  let fillersHeard = 0;
  let fillersSaid = 0;
  for (const [id, reference] of references) {
    const text = byId.get(id)?.text;
    if (text === undefined) failures++;
    werFree.push(text === undefined ? 1 : wer(reference, text));
    const said = fillersOf(reference);
    fillersSaid += said.length;
    fillersHeard += Math.min(said.length, fillersOf(text ?? "").length);
  }
  const latencies = results
    .map((result) => result.latencyMs)
    .filter((ms): ms is number => ms !== undefined);
  const mean = (values: number[]) =>
    values.reduce((sum, value) => sum + value, 0) / values.length;
  const errorKept = items.length === 0 ? 0 : kept / items.length;
  return {
    candidate,
    scripted: items.length,
    failures,
    errorKept,
    errorLost: lost,
    werScripted: werScripted.length === 0 ? 0 : mean(werScripted),
    werFree: werFree.length === 0 ? null : mean(werFree),
    fillerCapture: fillersSaid === 0 ? null : fillersHeard / fillersSaid,
    latencyP50: percentile(latencies, 0.5),
    latencyP90: percentile(latencies, 0.9),
    passes: { errorKept: errorKept >= asrThresholds.errorKept },
  };
}
