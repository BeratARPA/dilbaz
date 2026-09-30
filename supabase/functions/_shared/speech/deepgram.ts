/**
 * Deepgram pre-recorded transcription (docs/08-speech.md §3.1): the audio
 * bytes go in the body, the settings in the query (`speech_config.ts`).
 * Checked against Deepgram's documentation on 2026-09-30.
 */
import { speechConfig } from "../speech_config.ts";
import type {
  AudioInput,
  SpeechToText,
  SttFailure,
  SttResult,
  TranscriptWord,
} from "./types.ts";

type Fetch = typeof fetch;

interface DeepgramWord {
  word?: string;
  start?: number;
  end?: number;
  confidence?: number;
}

interface DeepgramResponse {
  metadata?: { duration?: number };
  results?: {
    channels?: {
      alternatives?: { transcript?: string; words?: DeepgramWord[] }[];
    }[];
  };
}

/** Maps a refused request to a failure (Deepgram's documented statuses). */
export function failureOf(status: number): SttFailure {
  if (status === 400 || status === 413 || status === 415) return "bad_audio";
  if (status === 401 || status === 403) return "provider_auth";
  if (status === 402) return "provider_quota";
  if (status === 429) return "provider_busy";
  return "provider_error";
}

export function deepgramStt(
  apiKey: string,
  fetcher: Fetch = fetch,
): SpeechToText {
  const config = speechConfig.sttEnglish;
  const url = `${config.endpoint}?${new URLSearchParams(config.params)}`;
  return {
    provider: config.provider,
    async transcribe(audio: AudioInput): Promise<SttResult> {
      let response: Response;
      try {
        response = await fetcher(url, {
          method: "POST",
          headers: {
            Authorization: `Token ${apiKey}`,
            "Content-Type": audio.contentType,
          },
          body: audio.bytes,
        });
      } catch {
        return { ok: false, failure: "network" };
      }
      if (!response.ok) {
        await response.body?.cancel();
        return { ok: false, failure: failureOf(response.status) };
      }
      const body = await response.json() as DeepgramResponse;
      // Silence gives no alternative: an empty transcript.
      const best = body.results?.channels?.[0]?.alternatives?.[0];
      const words: TranscriptWord[] = (best?.words ?? []).map((word) => ({
        w: word.word ?? "",
        startMs: Math.round((word.start ?? 0) * 1000),
        endMs: Math.round((word.end ?? 0) * 1000),
        conf: word.confidence,
      }));
      return {
        ok: true,
        transcript: {
          text: best?.transcript ?? "",
          words,
          provider: config.provider,
          model: config.model,
          durationMs: Math.round((body.metadata?.duration ?? 0) * 1000),
        },
      };
    },
  };
}
