/**
 * Closed lists of a language pair that the tutor's prompts carry and its
 * answers are checked against (docs/07-ai-tutor.md §1.4, §5; I-11).
 *
 * They come from the pair pack (`content/packs/<l1>-<l2>/`) and are
 * generated into `<pair>.ts` by `generate.ts`; a test keeps them in step.
 */

export type ErrorCategory =
  | "grammar"
  | "vocabulary"
  | "pronunciation"
  | "perception"
  | "pragmatics";

export interface ErrorTag {
  code: string;
  category: ErrorCategory;
  /** What the error is, in the learner's language. */
  description: string;
  /** One "wrong → right" example. */
  example: string;
}

export interface Catalog {
  /** The pair pack it comes from, such as `tr-en@1`. */
  pack: string;
  errorTags: ErrorTag[];
  /** H3 rule note of each grammar code (docs/03 §0.5). */
  ruleNotes: Record<string, string>;
}
