/**
 * The single place for LLM settings (docs/07-ai-tutor.md §2–§3, ADR-0009).
 *
 * Only free tiers are used. Each route calls its chain in order: primary
 * model, then the fallbacks; when none answers, the client continues with
 * the deterministic path. Model ids appear nowhere else in the functions
 * (a test enforces this). Changing a model, the order or a prompt requires
 * an eval run and the user's decision (docs/07 §8).
 *
 * Provider APIs checked against their documentation on 2026-09-30.
 */

/** Semantic thinking depth; each adapter maps it to its provider. */
export type Effort = "low" | "medium" | "high";

export type ProviderId = "gemini" | "groq";

export interface ProviderConfig {
  readonly endpoint: string;
  /** Secret holding the API key (Supabase secrets, docs/12 §7). */
  readonly keyEnv: string;
  /** Time zone whose midnight resets the daily quotas. */
  readonly quotaDay: string;
  /**
   * The free tier may use the text to improve the provider's products:
   * only for learners who agreed (`ai_data_consent`, ADR-0009).
   */
  readonly needsConsent: boolean;
}

export interface ModelConfig {
  readonly provider: ProviderId;
  /** Free daily requests for the project (AI Studio / Groq console). */
  readonly requestsPerDay: number;
  /** Free daily tokens, where the provider limits them. */
  readonly tokensPerDay?: number;
  /** The model hears audio sent with the message. */
  readonly audio?: boolean;
}

export interface RouteConfig {
  /** Models in the order they are tried; empty = route not open yet. */
  readonly chain: readonly string[];
  readonly effort: Effort;
  /** Output ceiling; kept generous because truncation costs a retry. */
  readonly maxTokens: number;
  /** Time one provider call may take before the next one is tried. */
  readonly timeoutMs: number;
}

export type TutorRoute =
  | "answer_check"
  | "speaking_annotate"
  | "gap_suggest"
  | "pron_check"
  | "roleplay_turn"
  | "roleplay_debrief"
  | "writing_feedback"
  | "mediation_check"
  | "comprehension_check";

/** Routes of later phases: their models are chosen by that phase's eval. */
const later = (
  effort: Effort,
  maxTokens: number,
): RouteConfig => ({ chain: [], effort, maxTokens, timeoutMs: 30_000 });

export const llmConfig = {
  providers: {
    gemini: {
      endpoint: "https://generativelanguage.googleapis.com/v1beta",
      keyEnv: "GEMINI_API_KEY",
      quotaDay: "America/Los_Angeles",
      needsConsent: true,
    },
    groq: {
      endpoint: "https://api.groq.com/openai/v1",
      keyEnv: "GROQ_API_KEY",
      quotaDay: "UTC",
      needsConsent: false,
    },
  } satisfies Record<ProviderId, ProviderConfig>,

  /** Free-tier limits as of 2026-09-26 (ADR-0009); the consoles decide. */
  models: {
    "gemini-3.1-flash-lite": {
      provider: "gemini",
      requestsPerDay: 500,
      audio: true,
    },
    "gemini-3.5-flash": {
      provider: "gemini",
      requestsPerDay: 20,
      audio: true,
    },
    "openai/gpt-oss-120b": {
      provider: "groq",
      requestsPerDay: 1000,
      tokensPerDay: 200_000,
    },
  } satisfies Record<string, ModelConfig> as Record<string, ModelConfig>,

  /** Each of the two learners may use this share of every quota. */
  fairShare: 0.5,

  routes: {
    // Groq missed the thresholds here (2026-10-10: 68.5 % right, 14.9 %
    // of right answers called wrong); without Gemini the card is judged by
    // the engine alone (docs/07 §2).
    answer_check: {
      chain: ["gemini-3.1-flash-lite"],
      effort: "low",
      maxTokens: 4000,
      timeoutMs: 15_000,
    },
    gap_suggest: {
      chain: [
        "gemini-3.5-flash",
        "gemini-3.1-flash-lite",
        "openai/gpt-oss-120b",
      ],
      effort: "low",
      maxTokens: 3000,
      timeoutMs: 20_000,
    },
    speaking_annotate: {
      chain: ["gemini-3.5-flash", "gemini-3.1-flash-lite"],
      effort: "medium",
      maxTokens: 12000,
      timeoutMs: 60_000,
    },
    // Hears a shadowed sentence (ADR-0011): only models that hear. Closed
    // until one passes the eval: Flash-Lite missed the thresholds
    // (2026-10-17: @1 14 of 21 right sentences given a problem; @2 a third
    // of the mistakes found). Shadowing goes on with recognition alone.
    pron_check: {
      chain: [],
      effort: "low",
      maxTokens: 3000,
      timeoutMs: 30_000,
    },
    roleplay_turn: later("low", 3000),
    comprehension_check: later("low", 3000),
    roleplay_debrief: later("medium", 12000),
    writing_feedback: later("medium", 12000),
    mediation_check: later("medium", 12000),
  } satisfies Record<TutorRoute, RouteConfig>,

  /** Monthly speaking test annotations think deeper (docs/07 §2). */
  assessmentEffort: "high" as Effort,
} as const;
