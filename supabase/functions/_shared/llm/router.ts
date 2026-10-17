/**
 * The provider chain of one route (docs/07-ai-tutor.md §3, §7; ADR-0009):
 * primary model → fallbacks → a code that sends the client down the
 * deterministic path.
 *
 * - A model is skipped without the learner's data consent where its
 *   provider needs one, above the learner's fair share, or while it is
 *   cooling down after a 429.
 * - An answer that does not pass the route's check is asked for once more,
 *   and so is a truncated one (with twice the output ceiling); then the
 *   next model is tried.
 * - Every call is recorded for `llm_usage`, whatever its outcome.
 */
import { llmConfig, type ProviderId } from "../llm_config.ts";
import { type ModelUse, quotaDayEnd, withinShare } from "./quota.ts";
import type { LlmFailure, LlmModel, LlmRequest } from "./types.ts";

/** One provider call, as `llm_usage` stores it. */
export interface CallRecord {
  provider: ProviderId;
  model: string;
  inputTokens: number | null;
  outputTokens: number | null;
  cachedTokens: number | null;
  /** `stop`, `invalid` or the failure code. */
  stopReason: string;
  latencyMs: number;
}

/** Why no model answered; the client then checks without the LLM. */
export type ChainFailure =
  /** Every model is past the learner's share or its quota. */
  | "quota_exhausted"
  /** Every model that was asked refused. */
  | "llm_refused"
  | "llm_failed"
  /** No model can be asked: no key, or no consent where one is needed. */
  | "llm_unavailable";

export type ChainResult<T> =
  | { ok: true; value: T; model: LlmModel; calls: CallRecord[] }
  | { ok: false; code: ChainFailure; calls: CallRecord[] };

/** Models to leave alone for a while after a 429, per isolate. */
export class Cooldown {
  readonly #until = new Map<string, { at: number; why: "quota" | "busy" }>();

  /** Why [model] waits at [now]: a spent daily quota, a per-minute limit,
   * or null when it may be tried. */
  blocked(model: string, now: number): "quota" | "busy" | null {
    const hold = this.#until.get(model);
    return hold !== undefined && hold.at > now ? hold.why : null;
  }

  hold(model: string, until: number, why: "quota" | "busy" = "quota"): void {
    this.#until.set(model, { at: until, why });
  }
}

/** Longest wait after a per-minute limit before the model is tried again. */
const maxBusyMs = 10 * 60_000;
const defaultBusyMs = 30_000;

export interface ChainDeps {
  /** The route's chain, in order, for the models whose key is set. */
  models: readonly LlmModel[];
  /** `ai_data_consent` of the learner. */
  consent: boolean;
  /** The learner's use of each model today. */
  use: ReadonlyMap<string, ModelUse>;
  cooldown: Cooldown;
  now: () => number;
}

export async function runChain<T>(
  deps: ChainDeps,
  request: LlmRequest,
  accept: (text: string) => T | null,
): Promise<ChainResult<T>> {
  const calls: CallRecord[] = [];
  const ends: ("quota" | "refused" | "failed")[] = [];

  for (const model of deps.models) {
    const config = llmConfig.models[model.id];
    const provider = llmConfig.providers[model.provider];
    if (!config || (provider.needsConsent && !deps.consent)) continue;
    const use = deps.use.get(model.id) ?? { requests: 0, tokens: 0 };
    // A per-minute limit is a model busy for now, not a day's share spent.
    const blocked = deps.cooldown.blocked(model.id, deps.now());
    if (blocked === "busy") {
      ends.push("failed");
      continue;
    }
    if (blocked === "quota" || !withinShare(config, use)) {
      ends.push("quota");
      continue;
    }

    let maxTokens = request.maxTokens;
    let askedAgain = false;
    let widened = false;
    let end: LlmFailure;
    for (;;) {
      const started = deps.now();
      const outcome = await model.generate({ ...request, maxTokens });
      const usage = outcome.usage;
      const record: CallRecord = {
        provider: model.provider,
        model: model.id,
        inputTokens: usage?.inputTokens ?? null,
        outputTokens: usage?.outputTokens ?? null,
        cachedTokens: usage?.cachedTokens ?? null,
        stopReason: outcome.ok ? outcome.stopReason : outcome.failure,
        latencyMs: Math.round(deps.now() - started),
      };
      calls.push(record);
      if (outcome.ok) {
        const value = accept(outcome.text);
        if (value !== null) return { ok: true, value, model, calls };
        record.stopReason = "invalid";
        end = "invalid";
      } else {
        end = outcome.failure;
      }
      if (end === "invalid" && !askedAgain) {
        askedAgain = true;
        continue;
      }
      if (end === "length" && !widened) {
        widened = true;
        maxTokens *= 2;
        continue;
      }
      if (!outcome.ok && (end === "quota" || end === "busy")) {
        const now = deps.now();
        deps.cooldown.hold(
          model.id,
          end === "quota"
            ? quotaDayEnd(provider.quotaDay, new Date(now)).getTime()
            : now + Math.min(outcome.retryAfterMs ?? defaultBusyMs, maxBusyMs),
          end,
        );
      }
      break;
    }
    ends.push(
      end === "quota" ? "quota" : end === "refused" ? "refused" : "failed",
    );
  }

  const code: ChainFailure = ends.length === 0
    ? "llm_unavailable"
    : ends.includes("failed")
    ? "llm_failed"
    : ends.includes("refused")
    ? "llm_refused"
    : "quota_exhausted";
  return { ok: false, code, calls };
}
