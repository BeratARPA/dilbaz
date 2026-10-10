/**
 * `speech` function: speech recognition behind one provider-independent
 * route (`/speech/transcribe`, docs/08-speech.md §5, docs/12 §7).
 *
 * A card answer comes as audio in the request body and is not stored
 * (docs/08 §5.1). Every transcription is recorded in `speech_usage`. No
 * transcript ever reaches the logs.
 *
 * Dependencies are injected so that the route is tested without network
 * access.
 */
import type { UserVerifier } from "../_shared/auth.ts";
import { json, jsonError, preflight } from "../_shared/http.ts";
import { logEvent, type LogSink } from "../_shared/log.ts";
import { speechConfig } from "../_shared/speech_config.ts";
import type { SpeechToText, SttFailure } from "../_shared/speech/types.ts";

/** One row of `speech_usage`. */
export interface SpeechUsage {
  profileId: string;
  provider: string;
  kind: "stt" | "pron" | "tts";
  seconds: number;
  costUsd: number;
}

export interface SpeechDeps {
  verifyUser: UserVerifier;
  /** English recognition; null while its key is not set. */
  english: SpeechToText | null;
  /**
   * Turkish recognition for devices that cannot do it themselves; null
   * while its key is not set (docs/08 §3.1).
   */
  turkish: SpeechToText | null;
  recordUsage: (usage: SpeechUsage) => Promise<void>;
  logSink?: LogSink;
  now?: () => number;
}

/** Status and code the client sees for a provider failure. */
const failureResponses: Record<SttFailure, [number, string]> = {
  bad_audio: [422, "bad_audio"],
  provider_auth: [503, "stt_unavailable"],
  provider_quota: [503, "stt_quota"],
  provider_busy: [503, "stt_busy"],
  provider_error: [502, "stt_failed"],
  network: [502, "stt_failed"],
};

/** Route name after the `speech` segment, or null when absent. */
export function routeOf(url: string): string | null {
  const segments = new URL(url).pathname.split("/").filter(Boolean);
  const index = segments.indexOf("speech");
  return index >= 0 && index + 1 < segments.length ? segments[index + 1] : null;
}

/** USD a transcription of [seconds] takes from the Deepgram credit. */
export function sttCost(seconds: number): number {
  const micro = (seconds / 60) * speechConfig.pricing.deepgramPerMinute *
    1_000_000;
  return Math.round(micro) / 1_000_000;
}

/** What a transcription costs: the free tiers nothing (ADR-0009). */
export function costOf(provider: string, seconds: number): number {
  return provider === speechConfig.sttEnglish.provider ? sttCost(seconds) : 0;
}

export function createSpeechHandler(deps: SpeechDeps) {
  const now = deps.now ?? (() => performance.now());
  const limits = speechConfig.upload;

  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return preflight();

    const started = now();
    const requestId = crypto.randomUUID();
    const route = routeOf(request.url);

    const finish = (
      response: Response,
      code?: string,
      userId?: string,
      model?: string,
    ): Response => {
      logEvent(
        response.status >= 500 ? "error" : "info",
        "request",
        {
          fn: "speech",
          requestId,
          route: route ?? undefined,
          userId,
          status: response.status,
          code,
          model,
          durationMs: Math.round(now() - started),
        },
        deps.logSink,
      );
      return response;
    };

    if (route !== "transcribe") {
      return finish(jsonError(404, "unknown_route"), "unknown_route");
    }
    if (request.method !== "POST") {
      return finish(jsonError(405, "method_not_allowed"), "method_not_allowed");
    }

    const auth = await deps.verifyUser(request);
    if (!auth.ok) return finish(jsonError(auth.status, auth.code), auth.code);
    const userId = auth.userId;
    const fail = (status: number, code: string, logged = code) =>
      finish(jsonError(status, code), logged, userId);

    // Turkish comes here only where the device cannot recognize it.
    const lang = new URL(request.url).searchParams.get("lang") ?? "en";
    const recognizers: Record<string, SpeechToText | null> = {
      en: deps.english,
      tr: deps.turkish,
    };
    if (!Object.hasOwn(recognizers, lang)) {
      return fail(400, "unsupported_language");
    }
    const transcriber = recognizers[lang];
    if (transcriber === null) return fail(503, "stt_unavailable");

    const contentType = (request.headers.get("content-type") ?? "")
      .split(";")[0].trim().toLowerCase();
    if (!(limits.types as readonly string[]).includes(contentType)) {
      return fail(415, "unsupported_audio");
    }
    const declared = Number(request.headers.get("content-length") ?? "0");
    if (declared > limits.maxBytes) return fail(413, "audio_too_large");
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (bytes.byteLength > limits.maxBytes) return fail(413, "audio_too_large");
    if (bytes.byteLength === 0) return fail(400, "empty_audio");

    const result = await transcriber.transcribe({ bytes, contentType });
    if (!result.ok) {
      const [status, code] = failureResponses[result.failure];
      return fail(status, code, result.failure);
    }
    const transcript = result.transcript;
    const seconds = transcript.durationMs / 1000;
    try {
      await deps.recordUsage({
        profileId: userId,
        provider: transcript.provider,
        kind: "stt",
        seconds,
        costUsd: costOf(transcript.provider, seconds),
      });
    } catch {
      // The learner still gets the transcript; the missing row is logged.
      logEvent("warn", "usage_not_recorded", {
        fn: "speech",
        requestId,
        route,
        userId,
      }, deps.logSink);
    }
    return finish(json(transcript), undefined, userId, transcript.model);
  };
}
