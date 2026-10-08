/**
 * Groq Whisper transcription (docs/08-speech.md §3.1): the Turkish fallback
 * where the device cannot recognize Turkish. The audio goes as a multipart
 * file with the model and the language (`speech_config.ts`). Checked
 * against Groq's documentation on 2026-10-08.
 */
import { speechConfig } from "../speech_config.ts";
import type {
  AudioInput,
  SpeechToText,
  SttFailure,
  SttResult,
} from "./types.ts";

type Fetch = typeof fetch;

interface GroqTranscription {
  text?: string;
  /** Seconds of audio (`verbose_json`). */
  duration?: number;
  segments?: { end?: number }[];
}

/** File name endings Groq reads the format from. */
const extensions: Record<string, string> = {
  "audio/mp4": "m4a",
  "audio/aac": "aac",
  "audio/wav": "wav",
  "audio/webm": "webm",
  "audio/ogg": "ogg",
};

/** Maps a refused request to a failure (Groq's documented statuses). */
export function groqFailureOf(response: Response): SttFailure {
  const status = response.status;
  if (status === 400 || status === 413 || status === 415 || status === 422) {
    return "bad_audio";
  }
  if (status === 401 || status === 403) return "provider_auth";
  if (status === 429) {
    // No requests left today: the daily quota, not a passing limit.
    return response.headers.get("x-ratelimit-remaining-requests") === "0"
      ? "provider_quota"
      : "provider_busy";
  }
  if (status === 498 || status === 503) return "provider_busy";
  return "provider_error";
}

export function groqStt(apiKey: string, fetcher: Fetch = fetch): SpeechToText {
  const config = speechConfig.sttTurkish.serverFallback;
  return {
    provider: config.provider,
    async transcribe(audio: AudioInput): Promise<SttResult> {
      const form = new FormData();
      const extension = extensions[audio.contentType] ?? "m4a";
      form.append(
        "file",
        new Blob([audio.bytes], { type: audio.contentType }),
        `audio.${extension}`,
      );
      form.append("model", config.model);
      form.append("language", config.language);
      form.append("response_format", "verbose_json");
      form.append("temperature", "0");
      let response: Response;
      try {
        response = await fetcher(config.endpoint, {
          method: "POST",
          headers: { Authorization: `Bearer ${apiKey}` },
          body: form,
        });
      } catch {
        return { ok: false, failure: "network" };
      }
      if (!response.ok) {
        await response.body?.cancel();
        return { ok: false, failure: groqFailureOf(response) };
      }
      const body = await response.json() as GroqTranscription;
      const seconds = body.duration ?? body.segments?.at(-1)?.end ?? 0;
      return {
        ok: true,
        transcript: {
          text: (body.text ?? "").trim(),
          words: [],
          provider: config.provider,
          model: config.model,
          durationMs: Math.round(seconds * 1000),
        },
      };
    },
  };
}
