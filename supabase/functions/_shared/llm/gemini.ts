/**
 * Gemini `generateContent` over REST (docs/07-ai-tutor.md §3): the fixed
 * prompt as the system instruction, the answer's JSON Schema as
 * `responseJsonSchema`, the effort as `thinkingConfig.thinkingLevel`; a
 * recording goes before the text as `inlineData` (a request ≤ 20 MB).
 * Checked against the Gemini API reference on 2026-09-30; audio input on
 * 2026-10-17.
 */
import { type Effort, llmConfig } from "../llm_config.ts";
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

const thinkingLevel: Record<Effort, string> = {
  low: "LOW",
  medium: "MEDIUM",
  high: "HIGH",
};

interface GeminiPart {
  text?: string;
  thought?: boolean;
}

interface GeminiResponse {
  candidates?: {
    content?: { parts?: GeminiPart[] };
    finishReason?: string;
  }[];
  promptFeedback?: { blockReason?: string };
  usageMetadata?: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
    thoughtsTokenCount?: number;
    cachedContentTokenCount?: number;
  };
}

interface GeminiError {
  error?: { details?: { retryDelay?: string }[] };
}

function usageOf(body: GeminiResponse): LlmUsage {
  const meta = body.usageMetadata ?? {};
  return {
    inputTokens: meta.promptTokenCount ?? 0,
    // Thinking is billed and limited as output.
    outputTokens: (meta.candidatesTokenCount ?? 0) +
      (meta.thoughtsTokenCount ?? 0),
    cachedTokens: meta.cachedContentTokenCount ?? 0,
  };
}

/** A refused call's failure, from its status and error body. */
export function geminiFailure(status: number, body: string): LlmFailure {
  if (status === 429) {
    // RESOURCE_EXHAUSTED names the quota: a daily one lasts until midnight.
    return /PerDay/i.test(body) ? "quota" : "busy";
  }
  if (status === 401 || status === 403) return "auth";
  if (status === 400 || status === 404) return "bad_request";
  if (status === 503) return "busy";
  return "server";
}

function retryDelayOf(body: string): number | undefined {
  try {
    const details = (JSON.parse(body) as GeminiError).error?.details ?? [];
    return secondsToMs(details.find((d) => d.retryDelay)?.retryDelay);
  } catch {
    return undefined;
  }
}

export function geminiModel(
  id: string,
  apiKey: string,
  fetcher: Fetch = fetch,
): LlmModel {
  const url =
    `${llmConfig.providers.gemini.endpoint}/models/${id}:generateContent`;
  return {
    id,
    provider: "gemini",
    async generate(request: LlmRequest): Promise<LlmOutcome> {
      const response = await timedFetch(fetcher, url, {
        method: "POST",
        headers: {
          "x-goog-api-key": apiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: request.system }] },
          contents: [{
            role: "user",
            parts: [
              ...(request.audio
                ? [{
                  inlineData: {
                    mimeType: request.audio.mimeType,
                    data: request.audio.data,
                  },
                }]
                : []),
              { text: request.user },
            ],
          }],
          generationConfig: {
            responseMimeType: "application/json",
            responseJsonSchema: request.schema,
            maxOutputTokens: request.maxTokens,
            thinkingConfig: { thinkingLevel: thinkingLevel[request.effort] },
          },
        }),
      }, request.timeoutMs);
      if (typeof response === "string") return { ok: false, failure: response };
      if (!response.ok) {
        const text = await response.text();
        return {
          ok: false,
          failure: geminiFailure(response.status, text),
          retryAfterMs: retryDelayOf(text),
        };
      }
      const body = await response.json() as GeminiResponse;
      const usage = usageOf(body);
      if (body.promptFeedback?.blockReason) {
        return { ok: false, failure: "refused", usage };
      }
      const candidate = body.candidates?.[0];
      const finish = candidate?.finishReason ?? "";
      if (finish === "MAX_TOKENS") {
        return { ok: false, failure: "length", usage };
      }
      if (finish !== "STOP") return { ok: false, failure: "refused", usage };
      const text = (candidate?.content?.parts ?? [])
        .filter((part) => !part.thought)
        .map((part) => part.text ?? "")
        .join("");
      return { ok: true, text, usage, stopReason: "stop" };
    },
  };
}
