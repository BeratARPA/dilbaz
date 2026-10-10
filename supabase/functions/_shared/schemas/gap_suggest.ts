/**
 * `gap_suggest` contract (docs/07-ai-tutor.md §4.3).
 *
 * - `GapSuggestInput`: what the learner could not say, in their language,
 *   with where it came up (A19).
 * - `gapSuggestWire`: what the model must return. Bounds are checked here,
 *   not by the provider; `notes_l1` is "" when there is nothing to note.
 * - `GapSuggestOutput`: what the route returns.
 */
import { z } from "zod";
import { Ctx } from "./answer_check.ts";

export const gapContexts = [
  "live_class",
  "daily",
  "pair",
  "speaking_task",
  "media",
] as const;

export const registers = ["neutral", "informal", "formal"] as const;

export const GapSuggestInput = z.object({
  ctx: Ctx,
  l1_text: z.string().max(300),
  context: z.enum(gapContexts),
  note: z.string().max(200).optional(),
});

export type GapSuggestInput = z.infer<typeof GapSuggestInput>;

const sentence = z.string().trim().min(1).max(300);

export const gapSuggestWire = z.strictObject({
  /** How it is naturally said in that situation, at the learner's level. */
  l2_natural: sentence,
  /** The same with the learner's words: their level plus one at most. */
  l2_simple: sentence,
  /** The phrase worth keeping, with its meaning in the learner's language. */
  key_chunk: z.strictObject({
    text: z.string().trim().min(1).max(80),
    gloss_l1: z.string().trim().min(1).max(120),
  }),
  register: z.enum(registers),
  notes_l1: z.string().trim().max(300),
});

export type GapSuggestWire = z.infer<typeof gapSuggestWire>;

export interface GapSuggestOutput {
  l2_natural: string;
  l2_simple: string;
  key_chunk: { text: string; gloss_l1: string };
  register: typeof registers[number];
  notes_l1: string | null;
  /**
   * Words of `l2_simple` above the learner's level plus one, at A levels;
   * none above them (docs/07 §4.3).
   */
  above_level: string[];
  /** The answer is the one of the "simplify" call. */
  simplified: boolean;
  provider: string;
  model: string;
}
