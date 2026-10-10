import { assertEquals } from "@std/assert";
import { type GapCaseResult, scoreGap } from "./score_gap.ts";

const call = (latencyMs: number, stopReason = "stop") => ({
  stopReason,
  latencyMs,
  inputTokens: 2000,
  outputTokens: 100,
  cachedTokens: 1500,
});

const result = (
  id: string,
  level: string,
  above: string[][],
  extra: Partial<GapCaseResult> = {},
): GapCaseResult => ({
  id,
  model: "m",
  prompt: "gap_suggest@1",
  level,
  l2_natural: "I don't feel like going out tonight.",
  l2_simple: "I don't want to go out tonight.",
  key_chunk: { text: "go out", gloss_l1: "dışarı çıkmak" },
  notes_l1: null,
  above,
  simplified: false,
  calls: [call(800)],
  ...extra,
});

Deno.test("the level rule counts A-level answers only", () => {
  const score = scoreGap("m", [
    result("a", "A1", [["venture"]]),
    result("b", "A2", [["postpone", "indefinitely"]], { simplified: true }),
    result("c", "B1", [["notwithstanding", "albeit"]]),
    result("d", "A0", [[], ["one"]]),
  ]);
  assertEquals(score.levelChecked, 3);
  assertEquals(score.levelOk, 2 / 3);
  assertEquals(score.passes.levelOk, false);
  assertEquals(score.simplified, 1);
});

Deno.test("failures, chunks, notes, schema and latency are counted", () => {
  const score = scoreGap("m", [
    result("a", "A1", [[]]),
    result("b", "A1", [[]], {
      key_chunk: { text: "stay in", gloss_l1: "evde kalmak" },
      notes_l1: Array(21).fill("kelime").join(" "),
      calls: [call(500, "invalid"), call(900)],
    }),
    {
      id: "c",
      model: "m",
      prompt: "gap_suggest@1",
      level: "A1",
      code: "llm_failed",
      calls: [call(3000, "server")],
    },
  ]);
  assertEquals(score.cases, 3);
  assertEquals(score.failures, 1);
  assertEquals(score.levelOk, 1);
  assertEquals(score.passes.levelOk, true);
  assertEquals(score.chunkCopied, 0.5);
  assertEquals(score.longNotes, 1);
  assertEquals(score.schemaValid, 1 / 3);
  assertEquals(score.latencyP50, 1400);
  // (2000 - 1500 + 100) per call.
  assertEquals(score.tokensPerCase, 800);
});
