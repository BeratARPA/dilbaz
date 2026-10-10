/**
 * `answer_check` contract (docs/07-ai-tutor.md §4.1).
 *
 * - `AnswerCheckInput`: what the client sends after the deterministic check
 *   found no match (docs/03 §0.5).
 * - `answerCheckWire`: what the model must return. Error tags are the
 *   pair's closed list; error spans are quoted text, turned into character
 *   ranges on the server. Bounds are checked here, not by the provider.
 * - `AnswerCheckOutput`: what the route returns.
 */
import { z } from "zod";

export const levels = ["A0", "A1", "A2", "B1", "B2", "C1", "C2"] as const;

export const verdicts = [
  "correct",
  "acceptable_variant",
  "minor_error",
  "wrong",
  "off_target",
  "unintelligible",
  "uncertain",
] as const;

export type Verdict = typeof verdicts[number];

/** Verdicts that come with a hint ladder. */
export const errorVerdicts: readonly Verdict[] = [
  "minor_error",
  "wrong",
  "off_target",
];

/**
 * Error categories a card answer can show; pronunciation and perception
 * tags belong to speaking tasks and dictation.
 */
export const answerCheckCategories = ["grammar", "vocabulary", "pragmatics"];

const text = z.string().max(400);

export const Ctx = z.object({
  l1: z.string().min(2).max(8),
  l2: z.string().min(2).max(8),
  level: z.enum(levels),
  explain_in: z.enum(["l1", "l2"]),
});

export const AnswerCheckInput = z.object({
  ctx: Ctx,
  item: z.object({
    key: z.string().min(1).max(120),
    prompt_l1: text.min(1),
    reference_l2: text.min(1),
    /** Correct answers that say the card's target. */
    variants: z.array(text).max(30).default([]),
    /** Correct answers without the target (docs/03 §0.2). */
    alternatives: z.array(text).max(30).default([]),
    /** The words of the reference that the card practises. */
    target_span: text,
    grammar_codes: z.array(z.string().max(80)).max(10).default([]),
    context_note: z.string().max(200).optional(),
  }),
  response: z.object({
    text,
    source: z.enum(["asr", "typed"]),
    asr_confidence: z.number().min(0).max(1).optional(),
  }),
  attempt_no: z.union([z.literal(1), z.literal(2), z.literal(3)]),
  previous_responses: z.array(text).max(2).default([]),
});

export type AnswerCheckInput = z.infer<typeof AnswerCheckInput>;

/** The model's answer, with [tags] as the closed list. */
export function answerCheckWire(tags: readonly [string, ...string[]]) {
  const tag = z.enum(tags);
  return z.strictObject({
    verdict: z.enum(verdicts),
    target_ok: z.boolean(),
    error_tags: z.array(tag),
    /** The wrong words, quoted from the response. */
    error_spans: z.array(z.strictObject({ text: z.string(), tag })),
    ladder: z.strictObject({
      h1: z.string(),
      h2: z.string(),
      h3: z.string(),
      h4: z.string(),
    }),
    /** The response for `acceptable_variant`, else empty. */
    variant_to_learn: z.string(),
    confidence: z.number().min(0).max(1),
  });
}

export type AnswerCheckWire = z.infer<ReturnType<typeof answerCheckWire>>;

export interface AnswerCheckOutput {
  verdict: Verdict;
  target_ok: boolean;
  error_tags: string[];
  /** Character ranges in `response.text`, end exclusive. */
  error_spans: { start: number; end: number; tag: string }[];
  /** Empty hints are filled by the client's templates (docs/03 §0.5). */
  ladder: { h1: string; h2: string; h3: string; h4: string };
  variant_to_learn: string | null;
  confidence: number;
  /** The pair pack whose catalog the tags come from. */
  catalog: string;
  provider: string;
  model: string;
}
