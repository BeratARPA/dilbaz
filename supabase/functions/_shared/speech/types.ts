/**
 * Speech recognition behind one interface, whatever the provider
 * (docs/08-speech.md §3.3).
 */

export interface AudioInput {
  bytes: Uint8Array<ArrayBuffer>;
  /** Media type of [bytes], such as `audio/mp4`. */
  contentType: string;
}

export interface TranscriptWord {
  w: string;
  startMs: number;
  endMs: number;
  conf?: number;
}

export interface Transcript {
  /** Verbatim: fillers and the learner's own forms are kept. */
  text: string;
  words: TranscriptWord[];
  provider: string;
  model: string;
  /** Length of the audio. */
  durationMs: number;
}

/** Why a transcription did not come back; each maps to a stable code. */
export type SttFailure =
  | "bad_audio"
  | "provider_auth"
  | "provider_quota"
  | "provider_busy"
  | "provider_error"
  | "network";

export type SttResult =
  | { ok: true; transcript: Transcript }
  | { ok: false; failure: SttFailure };

export interface SpeechToText {
  /** The provider and model, for usage records. */
  readonly provider: string;
  transcribe(audio: AudioInput): Promise<SttResult>;
}
