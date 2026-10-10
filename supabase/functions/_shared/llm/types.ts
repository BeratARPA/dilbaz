/**
 * LLM providers behind one interface (docs/07-ai-tutor.md §3, ADR-0009).
 *
 * A route sends a fixed system prompt, a variable user message and the JSON
 * Schema of its answer; the adapter returns the answer's text or a failure
 * that decides what the router does next.
 */
import type { Effort, ProviderId } from "../llm_config.ts";

/** A JSON Schema in the subset both providers accept (`json_schema.ts`). */
export type JsonSchema = { [key: string]: unknown };

export interface LlmRequest {
  /** Rubric, catalog and examples: the same for every call of a route. */
  system: string;
  /** The call's own input. */
  user: string;
  /** Name of the answer's schema, such as `answer_check`. */
  schemaName: string;
  schema: JsonSchema;
  effort: Effort;
  maxTokens: number;
  timeoutMs: number;
}

export interface LlmUsage {
  inputTokens: number;
  outputTokens: number;
  /** Input tokens read from the provider's cache. */
  cachedTokens: number;
}

/** Why a call gave no usable text; each maps to a stable code. */
export type LlmFailure =
  /** The daily quota is spent: skip the model until its quota day ends. */
  | "quota"
  /** A per-minute limit or an overloaded provider: skip it for a while. */
  | "busy"
  | "auth"
  | "bad_request"
  /** Blocked by a safety filter or refused. */
  | "refused"
  /** The output ceiling was reached. */
  | "length"
  /** The text did not match the schema (also reported by the provider). */
  | "invalid"
  | "server"
  | "timeout"
  | "network";

export type LlmOutcome =
  | { ok: true; text: string; usage: LlmUsage; stopReason: string }
  | {
    ok: false;
    failure: LlmFailure;
    usage?: LlmUsage;
    /** How long the provider asked to wait, when it said. */
    retryAfterMs?: number;
  };

export interface LlmModel {
  readonly id: string;
  readonly provider: ProviderId;
  generate(request: LlmRequest): Promise<LlmOutcome>;
}

export type Fetch = typeof fetch;

/** Seconds as the providers write them ("12", "12s", "1.5s") → ms. */
export function secondsToMs(
  value: string | null | undefined,
): number | undefined {
  if (!value) return undefined;
  const seconds = Number.parseFloat(value.replace(/s$/, ""));
  return Number.isFinite(seconds) && seconds >= 0
    ? Math.round(seconds * 1000)
    : undefined;
}

/** Calls [fetcher] with a timeout; a timeout and a network error differ. */
export async function timedFetch(
  fetcher: Fetch,
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response | "timeout" | "network"> {
  try {
    return await fetcher(url, {
      ...init,
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    return error instanceof DOMException && error.name === "TimeoutError"
      ? "timeout"
      : "network";
  }
}
