/**
 * `tutor/gap_suggest` (docs/07-ai-tutor.md §4.3): the English for what the
 * learner could not say (A19).
 *
 * The model's answer is checked with zod; then the server checks the words
 * of `l2_simple` against the target pack's levels. At A levels, a sentence
 * with more than one word above the learner's level plus one gets a single
 * "simplify" call (docs/07 §8: at most one such word per sentence).
 */
import { lexiconFor } from "../_shared/levels/index.ts";
import { aboveLevel, type Lexicon, scaleOf } from "../_shared/levels/levels.ts";
import { providerSchema } from "../_shared/llm/json_schema.ts";
import type {
  CallRecord,
  ChainFailure,
  ChainResult,
} from "../_shared/llm/router.ts";
import type { JsonSchema, LlmModel } from "../_shared/llm/types.ts";
import {
  gapSuggestSystemPrompt,
  gapSuggestUserMessage,
} from "../_shared/prompts/gap_suggest.ts";
import {
  type GapSuggestInput,
  type GapSuggestOutput,
  type GapSuggestWire,
  gapSuggestWire,
} from "../_shared/schemas/gap_suggest.ts";

/** Most words above the level that one sentence may keep. */
export const maxAbovePerSentence = 1;

/** What gap_suggest needs for one target language, built once. */
export interface GapSuggestKit {
  system: string;
  schema: JsonSchema;
  lexicon: Lexicon;
}

const kits = new Map<string, GapSuggestKit>();

/** The kit of [l2], or null for a language without word levels. */
export function gapKitFor(l2: string): GapSuggestKit | null {
  const cached = kits.get(l2);
  if (cached) return cached;
  const lexicon = lexiconFor(l2);
  if (!lexicon) return null;
  const kit = {
    system: gapSuggestSystemPrompt(),
    schema: providerSchema(gapSuggestWire),
    lexicon,
  };
  kits.set(l2, kit);
  return kit;
}

/** The model's text as an answer, or null when it is not a valid one. */
export function parseGapWire(text: string): GapSuggestWire | null {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    return null;
  }
  const parsed = gapSuggestWire.safeParse(json);
  return parsed.success ? parsed.data : null;
}

/** Whether the level check applies: A levels only (docs/07 §4.3). */
const checked = (input: GapSuggestInput) =>
  scaleOf(input.ctx.level) <= scaleOf("A2");

/**
 * The words of `l2_simple` to simplify away: null when every sentence
 * keeps at most one word above the level, or the level is not checked.
 */
export function tooHard(
  input: GapSuggestInput,
  wire: GapSuggestWire,
  lexicon: Lexicon,
): string[] | null {
  if (!checked(input)) return null;
  const sentences = aboveLevel(wire.l2_simple, input.ctx.level, lexicon);
  if (sentences.every((words) => words.length <= maxAbovePerSentence)) {
    return null;
  }
  return [...new Set(sentences.flat())];
}

/** The route's answer from a valid model answer. */
export function gapOutput(
  input: GapSuggestInput,
  wire: GapSuggestWire,
  lexicon: Lexicon,
  served: { simplified: boolean; provider: string; model: string },
): GapSuggestOutput {
  return {
    l2_natural: wire.l2_natural,
    l2_simple: wire.l2_simple,
    key_chunk: wire.key_chunk,
    register: wire.register,
    notes_l1: wire.notes_l1 === "" ? null : wire.notes_l1,
    above_level: checked(input)
      ? [
        ...new Set(aboveLevel(wire.l2_simple, input.ctx.level, lexicon).flat()),
      ]
      : [],
    simplified: served.simplified,
    provider: served.provider,
    model: served.model,
  };
}

/** The route's result: an answer, or why none came; every call either way. */
export type GapSuggestResult =
  | { ok: true; output: GapSuggestOutput; model: LlmModel; calls: CallRecord[] }
  | { ok: false; code: ChainFailure; calls: CallRecord[] };

/**
 * The whole route: the first call, then one "simplify" call when the
 * answer is too hard. [ask] runs the provider chain for a user message;
 * it gets the calls made so far, which count toward the learner's share.
 */
export async function suggestGap(
  input: GapSuggestInput,
  kit: GapSuggestKit,
  ask: (
    user: string,
    earlier: CallRecord[],
  ) => Promise<ChainResult<GapSuggestWire>>,
): Promise<GapSuggestResult> {
  const first = await ask(gapSuggestUserMessage(input), []);
  if (!first.ok) return first;
  const calls = [...first.calls];
  let wire = first.value;
  let served = first.model;
  let simplified = false;
  const hard = tooHard(input, wire, kit.lexicon);
  if (hard) {
    const second = await ask(
      gapSuggestUserMessage(input, {
        previous: wire.l2_simple,
        above_level: hard,
      }),
      first.calls,
    );
    calls.push(...second.calls);
    if (second.ok) {
      wire = second.value;
      served = second.model;
      simplified = true;
    }
  }
  return {
    ok: true,
    output: gapOutput(input, wire, kit.lexicon, {
      simplified,
      provider: served.provider,
      model: served.id,
    }),
    model: served,
    calls,
  };
}
