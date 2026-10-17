/**
 * Groq chat completions, OpenAI compatible (docs/07-ai-tutor.md §3): the
 * answer's JSON Schema in strict mode (constrained decoding), the effort as
 * `reasoning_effort`, the reasoning text left out of the answer.
 * Checked against Groq's documentation on 2026-09-30.
 */
import { llmConfig } from "../llm_config.ts";
import {
  type Fetch,
  type LlmFailure,
  type LlmModel,
  type LlmOutcome,
  type LlmRequest,
  type LlmUsage,
  secondsToMs,
  timedFetch,
} from "./types.ts";

interface GroqResponse {
  choices?: { message?: { content?: string | null }; finish_reason?: string }[];
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
    prompt_tokens_details?: { cached_tokens?: number };
  };
}

function usageOf(body: GroqResponse): LlmUsage {
  const usage = body.usage ?? {};
  return {
    inputTokens: usage.prompt_tokens ?? 0,
    outputTokens: usage.completion_tokens ?? 0,
    cachedTokens: usage.prompt_tokens_details?.cached_tokens ?? 0,
  };
}

/** A refused call's failure, from its status, headers and error body. */
export function groqFailure(
  status: number,
  headers: Headers,
  body: string,
): LlmFailure {
  if (status === 429) {
    // A daily limit, not a per-minute one: no requests left today, or the
    // day's tokens (TPD), which only the message names; the headers count
    // tokens per minute.
    return headers.get("x-ratelimit-remaining-requests") === "0" ||
        body.includes("per day")
      ? "quota"
      : "busy";
  }
  if (status === 401 || status === 403) return "auth";
  // A schema the output could not satisfy is reported as a 400.
  if (status === 400 && body.includes("json_validate_failed")) return "invalid";
  if (status === 400 || status === 404 || status === 422) return "bad_request";
  if (status === 503) return "busy";
  return "server";
}

export function groqModel(
  id: string,
  apiKey: string,
  fetcher: Fetch = fetch,
): LlmModel {
  const url = `${llmConfig.providers.groq.endpoint}/chat/completions`;
  return {
    id,
    provider: "groq",
    async generate(request: LlmRequest): Promise<LlmOutcome> {
      // Chat models here do not hear: a recording is not theirs to judge.
      if (request.audio) return { ok: false, failure: "bad_request" };
      const response = await timedFetch(fetcher, url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: id,
          messages: [
            { role: "system", content: request.system },
            { role: "user", content: request.user },
          ],
          response_format: {
            type: "json_schema",
            json_schema: {
              name: request.schemaName,
              strict: true,
              schema: request.schema,
            },
          },
          reasoning_effort: request.effort,
          include_reasoning: false,
          max_completion_tokens: request.maxTokens,
        }),
      }, request.timeoutMs);
      if (typeof response === "string") return { ok: false, failure: response };
      if (!response.ok) {
        const text = await response.text();
        return {
          ok: false,
          failure: groqFailure(response.status, response.headers, text),
          retryAfterMs: secondsToMs(response.headers.get("retry-after")),
        };
      }
      const body = await response.json() as GroqResponse;
      const usage = usageOf(body);
      const choice = body.choices?.[0];
      const finish = choice?.finish_reason ?? "";
      if (finish === "length") return { ok: false, failure: "length", usage };
      if (finish !== "stop") return { ok: false, failure: "refused", usage };
      return {
        ok: true,
        text: choice?.message?.content ?? "",
        usage,
        stopReason: "stop",
      };
    },
  };
}
