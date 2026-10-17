import { assert, assertEquals } from "@std/assert";
import { dirname, fromFileUrl, join, relative } from "@std/path";
import { llmConfig } from "./llm_config.ts";
import { speechConfig } from "./speech_config.ts";

const efforts = ["low", "medium", "high"];

Deno.test("every route has a valid effort and a generous max_tokens", () => {
  for (const [route, config] of Object.entries(llmConfig.routes)) {
    assert(efforts.includes(config.effort), route);
    assert(config.maxTokens >= 3000, `${route} max_tokens too low`);
    assert(config.timeoutMs > 0, route);
  }
});

Deno.test("route settings follow docs/07 §2–§3", () => {
  // Groq missed the answer_check thresholds (docs/07 §8): no fallback model.
  assertEquals(llmConfig.routes.answer_check, {
    chain: ["gemini-3.1-flash-lite"],
    effort: "low",
    maxTokens: 4000,
    timeoutMs: 15_000,
  });
  assertEquals(llmConfig.routes.gap_suggest.chain[0], "gemini-3.5-flash");
  assertEquals(llmConfig.routes.speaking_annotate.effort, "medium");
  assertEquals(llmConfig.assessmentEffort, "high");
  assertEquals(llmConfig.fairShare, 0.5);
});

Deno.test("pronunciation is heard only by models that hear (ADR-0011)", () => {
  const route = llmConfig.routes.pron_check;
  assert(route.chain.length > 0);
  for (const id of route.chain) {
    assertEquals(llmConfig.models[id].audio, true, id);
    assertEquals(llmConfig.models[id].provider, "gemini", id);
  }
});

Deno.test("15 s of 16 kHz WAV fits a pron_check request", async () => {
  const { maxAudioBase64 } = await import("./schemas/pron_check.ts");
  const wav = 44 + speechConfig.pronunciation.seconds * 16_000 * 2;
  assert(Math.ceil(wav / 3) * 4 <= maxAudioBase64);
});

Deno.test("routes of later phases have no model until their eval", () => {
  for (
    const route of [
      "roleplay_turn",
      "roleplay_debrief",
      "writing_feedback",
      "mediation_check",
      "comprehension_check",
    ] as const
  ) {
    assertEquals(llmConfig.routes[route].chain, [], route);
  }
});

Deno.test("every model of a chain is configured with a free quota", () => {
  for (const [route, config] of Object.entries(llmConfig.routes)) {
    for (const id of config.chain) {
      const model = llmConfig.models[id];
      assert(model, `${route}: ${id} is not configured`);
      assert(model.requestsPerDay > 0, id);
      assert(llmConfig.providers[model.provider], id);
    }
  }
});

Deno.test("only free providers serve the tutor (ADR-0009)", () => {
  assertEquals(Object.keys(llmConfig.providers).sort(), ["gemini", "groq"]);
  // Gemini's free tier may use the text: only with the learner's consent.
  assertEquals(llmConfig.providers.gemini.needsConsent, true);
  assertEquals(llmConfig.providers.groq.needsConsent, false);
  assertEquals(llmConfig.providers.gemini.quotaDay, "America/Los_Angeles");
});

Deno.test("model ids appear only in llm_config.ts", async () => {
  const functionsDir = join(dirname(fromFileUrl(import.meta.url)), "..");
  const offenders: string[] = [];
  async function scan(dir: string) {
    for await (const entry of Deno.readDir(dir)) {
      const path = join(dir, entry.name);
      if (entry.isDirectory) {
        await scan(path);
      } else if (
        entry.name.endsWith(".ts") &&
        !entry.name.endsWith("_test.ts") &&
        entry.name !== "llm_config.ts" &&
        /["'`](claude-|gemini-|openai\/gpt-)/.test(
          await Deno.readTextFile(path),
        )
      ) {
        offenders.push(relative(functionsDir, path));
      }
    }
  }
  await scan(functionsDir);
  assertEquals(offenders, []);
});

Deno.test("every function deploys with the shared imports", async () => {
  const functionsDir = join(dirname(fromFileUrl(import.meta.url)), "..");
  const shared = JSON.parse(
    await Deno.readTextFile(join(functionsDir, "deno.json")),
  );
  let functions = 0;
  for await (const entry of Deno.readDir(functionsDir)) {
    if (!entry.isDirectory || entry.name.startsWith("_")) continue;
    functions++;
    const own = JSON.parse(
      await Deno.readTextFile(join(functionsDir, entry.name, "deno.json")),
    );
    assertEquals(own.imports, shared.imports, entry.name);
  }
  assert(functions >= 2);
});

Deno.test("English ASR is configured for verbatim transcripts", () => {
  const params = speechConfig.sttEnglish.params;
  assertEquals(params.model, speechConfig.sttEnglish.model);
  assertEquals(params.filler_words, "true");
  assertEquals(params.smart_format, "false");
  assertEquals(params.punctuate, "false");
  assertEquals(params.mip_opt_out, "true");
});

Deno.test("only free providers serve speech (ADR-0009)", () => {
  assertEquals(speechConfig.sttEnglish.provider, "deepgram");
  assertEquals(speechConfig.sttTurkish.onDevice, true);
  // Pronunciation is heard on the free Gemini tier (ADR-0011).
  assertEquals(speechConfig.pronunciation.route, "tutor/pron_check");
  assertEquals(speechConfig.tts.dynamic, "on-device");
  assert(speechConfig.pricing.deepgramPerMinute > 0);
});

Deno.test("a card answer and a two-minute task fit in one upload", () => {
  // 12 s of AAC at 32 kbps, and two minutes of it (docs/08 §4).
  assert(speechConfig.upload.maxBytes >= 120 * 32_000 / 8);
  assert(speechConfig.upload.types.includes("audio/mp4"));
});
