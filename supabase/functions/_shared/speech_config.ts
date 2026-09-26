/**
 * The single place for speech settings (docs/08-speech.md §3, ADR-0006).
 *
 * Which adapter serves which need is decided here; adapters live in
 * `_shared/speech/`. The ASR choice is confirmed by the Faz 2 bake-off.
 */

export const speechConfig = {
  /** S1: learner English must be transcribed verbatim (docs/08 §2). */
  sttEnglish: {
    provider: "deepgram",
    model: "nova-3",
    params: {
      language: "en",
      // Keep "uh/um" and learner errors; no formatting that rewrites words.
      filler_words: true,
      smart_format: false,
      punctuate: false,
      // Opt out of the model improvement program (docs/08 §9).
      mip_opt_out: true,
    },
  },

  /** S2: Turkish capture for "Söyleyemediklerim". */
  sttTurkish: { provider: "azure", locale: "tr-TR" },

  /** S3: pronunciation assessment against a reference text. */
  pronunciation: {
    provider: "azure",
    // IPA phoneme names and prosody exist only for en-US (docs/08 §7).
    locale: "en-US",
    maxSeconds: 30,
    enableMiscue: true,
    audioFormat: "wav-pcm16-16khz-mono",
  },

  /** S4: dynamic TTS, cached in the `tts-cache` bucket. */
  tts: {
    provider: "azure",
    cacheBucket: "tts-cache",
    slowRate: 0.8,
  },

  /** USD prices verified 2026-09-25 (docs/08 §3.1); null = not yet priced. */
  pricing: {
    deepgramPerMinute: 0.0043,
    azureTtsPerMillionChars: 15,
    azureSttPerHour: null as number | null,
  },
} as const;
