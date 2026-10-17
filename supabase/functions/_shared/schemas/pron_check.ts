/**
 * `pron_check` contract (docs/07-ai-tutor.md §4.4, ADR-0011).
 *
 * - `PronCheckInput`: a shadowed sentence and its recording (WAV, ≤ 15 s).
 * - `pronCheckWire`: what the model must return: problems it is sure of,
 *   each a word of the sentence (its index) and a tag of the pair's closed
 *   pronunciation list, or `uncertain` when the recording cannot be judged.
 * - `PronCheckOutput`: what the route returns. No score is made: the
 *   engine picks what the learner sees (`pickPronIssues`).
 */
import { z } from "zod";
import { Ctx } from "./answer_check.ts";

/** Media types a recording may have: pronunciation needs PCM (docs/08 §4). */
export const pronAudioTypes = ["audio/wav"] as const;

/** 15 s of 16 kHz mono PCM16 is ~480 KB; base64 makes it ~640 KB. */
export const maxAudioBase64 = 700_000;

const base64 = /^[A-Za-z0-9+/]+={0,2}$/;

export const PronCheckInput = z.object({
  ctx: Ctx,
  /** The sentence the learner heard and repeated. */
  reference: z.string().trim().min(1).max(300),
  audio: z.object({
    data: z.string().min(1).max(maxAudioBase64).regex(base64),
    mime_type: z.enum(pronAudioTypes),
  }),
});

export type PronCheckInput = z.infer<typeof PronCheckInput>;

/** The model's answer, with the pair's pronunciation [tags]. */
export function pronCheckWire(tags: readonly [string, ...string[]]) {
  return z.strictObject({
    /** The recording is silent, noise, or not the sentence. */
    uncertain: z.boolean(),
    issues: z.array(
      z.strictObject({
        /** Index of the word in the numbered sentence. */
        i: z.number().int().min(0),
        tag: z.enum(tags),
        /** How the word sounded, in plain letters ("vork"). */
        heard: z.string(),
      }),
    ),
  });
}

export type PronCheckWire = z.infer<ReturnType<typeof pronCheckWire>>;

export interface PronIssue {
  i: number;
  /** The word of the sentence, as the server numbered it. */
  word: string;
  tag: string;
  heard: string;
}

export interface PronCheckOutput {
  uncertain: boolean;
  issues: PronIssue[];
  /** The pair pack whose catalog the tags come from. */
  catalog: string;
  prompt_version: string;
  provider: string;
  model: string;
}
