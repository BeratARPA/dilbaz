import { assertAlmostEquals, assertEquals } from "@std/assert";
import { calledWrong, type CaseResult, isGoldCorrect, score } from "./score.ts";

const stop = {
  stopReason: "stop",
  latencyMs: 800,
  inputTokens: 4000,
  outputTokens: 300,
  cachedTokens: 3500,
};
const none = { h1: "", h2: "", h3: "", h4: "" };

function result(fields: Partial<CaseResult>): CaseResult {
  return {
    id: "x",
    model: "m",
    prompt: "answer_check@1",
    level: "A1",
    expected: { verdicts: ["correct"], target_ok: true, tags: [] },
    verdict: "correct",
    target_ok: true,
    error_tags: [],
    ladder: none,
    leaked: [],
    servedLeaks: 0,
    calls: [stop],
    ...fields,
  };
}

Deno.test("a correct answer is gold-correct only if every accepted verdict is", () => {
  assertEquals(
    isGoldCorrect({
      verdicts: ["correct", "acceptable_variant"],
      target_ok: true,
      tags: [],
    }),
    true,
  );
  assertEquals(
    isGoldCorrect({
      verdicts: ["minor_error", "correct"],
      target_ok: true,
      tags: [],
    }),
    false,
  );
});

Deno.test("a miss for the card is wrong, off target, or a minor error in the target", () => {
  assertEquals(calledWrong(result({ verdict: "wrong" })), true);
  assertEquals(calledWrong(result({ verdict: "off_target" })), true);
  assertEquals(
    calledWrong(result({ verdict: "minor_error", target_ok: false })),
    true,
  );
  assertEquals(
    calledWrong(result({ verdict: "minor_error", target_ok: true })),
    false,
  );
  assertEquals(
    calledWrong(result({ verdict: "uncertain", target_ok: false })),
    false,
  );
  assertEquals(calledWrong(result({ verdict: undefined })), false, "a failure");
});

Deno.test("scores follow docs/07 §8", () => {
  const hints = {
    h1: "Bir kelime eksik.",
    h2: "'I' ile 'happy' arasına bak.",
    h3: "",
    h4: "I am happy.",
  };
  const results = [
    result({ id: "a" }),
    result({
      id: "b",
      expected: {
        verdicts: ["acceptable_variant"],
        target_ok: false,
        tags: [],
      },
      verdict: "wrong",
      target_ok: false,
    }),
    result({
      id: "c",
      expected: {
        verdicts: ["wrong", "minor_error"],
        target_ok: false,
        tags: ["be.missing"],
      },
      verdict: "wrong",
      target_ok: false,
      error_tags: ["be.missing"],
      ladder: hints,
      leaked: ["h3"],
      calls: [{ ...stop, stopReason: "invalid" }, stop],
    }),
    result({
      id: "d",
      expected: { verdicts: ["off_target"], target_ok: false, tags: [] },
      verdict: undefined,
      target_ok: undefined,
      code: "llm_failed",
      calls: [{
        stopReason: "network",
        latencyMs: 30,
        inputTokens: null,
        outputTokens: null,
        cachedTokens: null,
      }],
    }),
  ];

  const s = score("m", results);

  assertEquals(s.cases, 4);
  assertEquals(s.failures, 1);
  assertAlmostEquals(s.accuracy, 2 / 4);
  assertEquals(s.goldCorrect, 2);
  assertAlmostEquals(s.falseWrong, 1 / 2);
  assertEquals(s.targetOk, 1);
  assertEquals(s.tagHit, 1);
  // First calls that returned text: a, b and c's invalid one.
  assertAlmostEquals(s.schemaValid, 2 / 3);
  // c served two hints and had one blanked.
  assertEquals(s.leakServed, 0);
  assertAlmostEquals(s.leakRaw, 1 / 3);
  assertEquals(s.longHints, 0);
  assertEquals(s.latencyP50, 800);
  assertEquals(s.tokens, { input: 16000, cached: 14000, output: 1200 });
  assertEquals(s.passes, {
    accuracy: false,
    falseWrong: false,
    leakServed: true,
    schemaValid: false,
  });
});

Deno.test("a served hint that still leaks and a long A-level hint are counted", () => {
  const long = Array.from({ length: 21 }, () => "kelime").join(" ");
  const s = score("m", [
    result({
      expected: { verdicts: ["wrong"], target_ok: false, tags: [] },
      verdict: "wrong",
      target_ok: false,
      ladder: { h1: long, h2: "b", h3: "c", h4: "d" },
      servedLeaks: 1,
    }),
  ]);
  assertAlmostEquals(s.leakServed, 1 / 3);
  assertEquals(s.passes.leakServed, false);
  assertEquals(s.longHints, 1);
});

Deno.test("an empty run scores zero, not NaN", () => {
  const s = score("m", []);
  assertEquals([s.accuracy, s.falseWrong, s.schemaValid, s.latencyP95], [
    0,
    0,
    0,
    0,
  ]);
});
