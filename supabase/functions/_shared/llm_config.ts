/**
 * The single place for LLM settings (docs/07-ai-tutor.md §2–§3).
 *
 * Model ids appear nowhere else in the functions (a test enforces this).
 * Changing the model or a prompt requires an eval run and the user's
 * decision (docs/07 §8, ADR-0005).
 */

export type Effort = "low" | "medium" | "high" | "xhigh" | "max";

export interface RouteConfig {
  /** Thinking depth, sent as `output_config.effort`. */
  readonly effort: Effort;
  /** Output ceiling; kept generous because truncation costs a retry. */
  readonly maxTokens: number;
  /** Interactive routes use the server-side refusal fallback. */
  readonly interactive: boolean;
}

/** USD per million tokens. */
export interface ModelPricing {
  readonly input: number;
  readonly output: number;
  readonly cacheRead: number;
  readonly cacheWrite5m: number;
  readonly cacheWrite1h: number;
}

export type TutorRoute =
  | "answer_check"
  | "speaking_annotate"
  | "gap_suggest"
  | "roleplay_turn"
  | "roleplay_debrief"
  | "writing_feedback"
  | "mediation_check"
  | "comprehension_check";

/** Cache reads cost 0.1x input; 5-minute writes 1.25x, 1-hour writes 2x. */
function pricing(input: number, output: number): ModelPricing {
  return {
    input,
    output,
    cacheRead: input * 0.1,
    cacheWrite5m: input * 1.25,
    cacheWrite1h: input * 2,
  };
}

export const llmConfig = {
  /** Default model for every route (docs/07 §2). */
  model: "claude-opus-5",

  /** Per-user daily ceiling; above it routes answer `budget_exceeded`. */
  dailyBudgetUsd: 1.5,

  /** Server-side refusal fallback for interactive routes (docs/07 §3). */
  refusalFallback: {
    beta: "server-side-fallback-2026-07-01",
    fallbacks: "default",
  },

  routes: {
    answer_check: { effort: "low", maxTokens: 4000, interactive: true },
    gap_suggest: { effort: "low", maxTokens: 3000, interactive: true },
    roleplay_turn: { effort: "low", maxTokens: 3000, interactive: true },
    comprehension_check: { effort: "low", maxTokens: 3000, interactive: true },
    speaking_annotate: {
      effort: "medium",
      maxTokens: 12000,
      interactive: true,
    },
    roleplay_debrief: { effort: "medium", maxTokens: 12000, interactive: true },
    writing_feedback: { effort: "medium", maxTokens: 12000, interactive: true },
    mediation_check: { effort: "medium", maxTokens: 12000, interactive: true },
  } satisfies Record<TutorRoute, RouteConfig>,

  /** Monthly speaking test annotations run at a higher effort (docs/07 §2). */
  assessmentEffort: "high" as Effort,

  /**
   * First-party prices (2026-09). With `fallbacks: "default"` another model
   * may serve a request; it is billed at its own price, so known fallback
   * candidates are listed too. Unknown models are costed at the default
   * model's price.
   */
  pricing: {
    "claude-opus-5": pricing(5, 25),
    "claude-opus-4-8": pricing(5, 25),
    "claude-opus-4-7": pricing(5, 25),
    "claude-sonnet-5": pricing(2, 10),
    "claude-haiku-4-5": pricing(1, 5),
  } as Record<string, ModelPricing>,
} as const;
