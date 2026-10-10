/**
 * The single place for speech settings (docs/08-speech.md §3, ADR-0006,
 * ADR-0009).
 *
 * Which provider serves which need is decided here; adapters live in
 * `_shared/speech/`. Only free providers are used (ADR-0009); the English
 * ASR choice is confirmed by the Faz 2 bake-off.
 */

export const speechConfig = {
  /**
   * S1: learner English, transcribed verbatim (docs/08 §2) by Deepgram
   * Nova-3 on the sign-up credit.
   */
  sttEnglish: {
    provider: "deepgram",
    model: "nova-3",
    endpoint: "https://api.deepgram.com/v1/listen",
    params: {
      model: "nova-3",
      language: "en",
      // Keep "uh/um" and the learner's own words; nothing that rewrites.
      filler_words: "true",
      smart_format: "false",
      punctuate: "false",
      // Opt out of the model improvement program (docs/08 §9).
      mip_opt_out: "true",
    },
  },

  /**
   * S2: Turkish is recognized on the device (`speech_to_text`). Where the
   * device cannot (Windows, web, no Turkish installed), Groq's Whisper on
   * the free tier transcribes it here (docs/08 §3.1; Groq keeps no data,
   * ZDR). Checked against Groq's documentation on 2026-10-08.
   */
  sttTurkish: {
    onDevice: true,
    locale: "tr-TR",
    serverFallback: {
      provider: "groq",
      model: "whisper-large-v3",
      endpoint: "https://api.groq.com/openai/v1/audio/transcriptions",
      keyEnv: "GROQ_API_KEY",
      language: "tr",
    },
  },

  /** S3: pronunciation assessment is chosen at the start of Faz 2. */
  pronunciation: null,

  /**
   * S4: pack audio is made offline with Kokoro; dynamic speech is spoken
   * on the device (`flutter_tts`).
   */
  tts: { packs: "kokoro-82m", dynamic: "on-device" },

  /** Audio a request may carry in its body (docs/08 §4). */
  upload: {
    // Two minutes of AAC at 32 kbps, or 30 seconds of 16 kHz WAV, fit.
    maxBytes: 2 * 1024 * 1024,
    types: ["audio/mp4", "audio/aac", "audio/wav", "audio/webm", "audio/ogg"],
  },

  /**
   * USD per minute taken from a credit; free tiers are 0. Verified
   * 2026-09-25 (docs/08 §3.1).
   */
  pricing: { deepgramPerMinute: 0.0043 },
} as const;
