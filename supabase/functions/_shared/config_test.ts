import { assert, assertEquals } from "@std/assert";
import { dirname, fromFileUrl, join, relative } from "@std/path";
import { llmConfig } from "./llm_config.ts";
import { speechConfig } from "./speech_config.ts";

const efforts = ["low", "medium", "high", "xhigh", "max"];

Deno.test("every route has a valid effort and a generous max_tokens", () => {
  for (const [route, config] of Object.entries(llmConfig.routes)) {
    assert(efforts.includes(config.effort), route);
    assert(config.maxTokens >= 3000, `${route} max_tokens too low`);
  }
});

Deno.test("route settings follow docs/07 §2–§3", () => {
  assertEquals(llmConfig.model, "claude-opus-5");
  assertEquals(llmConfig.routes.answer_check, {
    effort: "low",
    maxTokens: 4000,
    interactive: true,
  });
  assertEquals(llmConfig.routes.speaking_annotate.effort, "medium");
  assertEquals(llmConfig.assessmentEffort, "high");
  assertEquals(llmConfig.dailyBudgetUsd, 1.5);
  assertEquals(llmConfig.refusalFallback, {
    beta: "server-side-fallback-2026-07-01",
    fallbacks: "default",
  });
});

Deno.test("the default model has a price", () => {
  assert(llmConfig.pricing[llmConfig.model] !== undefined);
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
        /["'`]claude-/.test(await Deno.readTextFile(path))
      ) {
        offenders.push(relative(functionsDir, path));
      }
    }
  }
  await scan(functionsDir);
  assertEquals(offenders, []);
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
  assertEquals(speechConfig.pronunciation, null);
  assertEquals(speechConfig.tts.dynamic, "on-device");
  assert(speechConfig.pricing.deepgramPerMinute > 0);
});

Deno.test("a card answer and a two-minute task fit in one upload", () => {
  // 12 s of AAC at 32 kbps, and two minutes of it (docs/08 §4).
  assert(speechConfig.upload.maxBytes >= 120 * 32_000 / 8);
  assert(speechConfig.upload.types.includes("audio/mp4"));
});
