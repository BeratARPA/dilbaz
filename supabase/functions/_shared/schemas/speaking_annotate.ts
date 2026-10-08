/**
 * `speaking_annotate` contract (docs/07-ai-tutor.md §4.2).
 *
 * - `SpeakingAnnotateInput`: a speaking task's transcript, word by word as
 *   recognized (with times), and the task.
 * - `speakingAnnotateWire`: what the model must return. Word indices point
 *   into the transcript; tags are the pair's closed list, codes the pack's
 *   grammar points. Bounds are checked here, not by the provider.
 * - `SpeakingAnnotateOutput`: what the route returns. No number is made
 *   here: the engine computes fluency, accuracy and complexity from these
 *   marks and the word times (docs/06 §3.3).
 */
import { z } from "zod";
import { Ctx } from "./answer_check.ts";

export const taskOutcomes = ["done", "partial", "not_done"] as const;
export const fillerKinds = ["l2", "l1"] as const;

const index = z.number().int().min(0);

export const SpeakingAnnotateInput = z.object({
  ctx: Ctx,
  task: z.object({
    /** The task as the learner read it. */
    prompt_l1: z.string().min(1).max(500),
    /** What doing the task means; the outcome is judged against it. */
    goal: z.string().min(1).max(500),
    can_do_codes: z.array(z.string().max(80)).max(5).default([]),
  }),
  /** Two minutes of speech is about 300 words. */
  words: z.array(z.object({
    i: index,
    w: z.string().trim().min(1).max(60),
    start_ms: index,
    end_ms: index,
  })).max(800),
  /** The monthly test: the annotation thinks deeper (docs/07 §2). */
  assessment: z.boolean().default(false),
});

export type SpeakingAnnotateInput = z.infer<typeof SpeakingAnnotateInput>;

/** The model's answer, with the pair's [tags] and the pack's [codes]. */
export function speakingAnnotateWire(
  tags: readonly [string, ...string[]],
  codes: readonly [string, ...string[]],
) {
  const tag = z.enum(tags);
  const severity = z.number().int().min(1).max(3);
  const span = { start_i: index, end_i: index };
  return z.strictObject({
    clauses: z.array(
      z.strictObject({ ...span, as_unit: index, error_free: z.boolean() }),
    ),
    errors: z.array(
      z.strictObject({ ...span, tag, correction: z.string(), severity }),
    ),
    fillers: z.array(z.strictObject({ i: index, kind: z.enum(fillerKinds) })),
    repairs: z.array(z.strictObject(span)),
    structures_used: z.array(
      z.strictObject({ code: z.enum(codes), ...span, correct: z.boolean() }),
    ),
    task_outcome: z.enum(taskOutcomes),
    strengths: z.array(z.string()),
    /** Errors worth practising; the engine picks at most three. */
    corrections: z.array(
      z.strictObject({
        original: z.string(),
        corrected: z.string(),
        /** What `corrected` means in the learner's language: its card's prompt. */
        meaning_l1: z.string(),
        tag,
        severity,
        ladder: z.strictObject({
          h1: z.string(),
          h2: z.string(),
          h3: z.string(),
        }),
      }),
    ),
  });
}

export type SpeakingAnnotateWire = z.infer<
  ReturnType<typeof speakingAnnotateWire>
>;

export interface SpeakingAnnotateOutput {
  clauses: SpeakingAnnotateWire["clauses"];
  errors: SpeakingAnnotateWire["errors"];
  fillers: SpeakingAnnotateWire["fillers"];
  repairs: SpeakingAnnotateWire["repairs"];
  structures_used: SpeakingAnnotateWire["structures_used"];
  task_outcome: typeof taskOutcomes[number];
  strengths: string[];
  /** Empty hints are filled by the client's templates (docs/03 §0.5). */
  corrections: SpeakingAnnotateWire["corrections"];
  /** The pair pack whose catalog the tags come from. */
  catalog: string;
  prompt_version: string;
  provider: string;
  model: string;
}
