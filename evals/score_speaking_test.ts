import { assertAlmostEquals, assertEquals } from "@std/assert";
import {
  matchErrors,
  scoreSpeaking,
  type SpeakingCaseResult,
} from "./score_speaking.ts";

const span = (start_i: number, end_i: number, tag = "be.missing") => ({
  start_i,
  end_i,
  tag,
});

const call = {
  stopReason: "stop",
  latencyMs: 2000,
  inputTokens: 9000,
  outputTokens: 900,
  cachedTokens: 8000,
};

function result(
  changes: Partial<SpeakingCaseResult> = {},
): SpeakingCaseResult {
  return {
    id: "sa01",
    model: "m",
    prompt: "speaking_annotate@1",
    level: "A1",
    expected: {
      errors: [span(1, 1), span(5, 6, "art.missing")],
      clauses: 4,
      efc: 0.5,
      outcome: "done",
    },
    errors: [span(1, 2), span(6, 6, "agr.3sg_s"), span(9, 9)],
    clauses: 4,
    efc: 0.75,
    outcome: "done",
    leaked: [],
    calls: [call],
    ...changes,
  };
}

Deno.test("a mark counts when it overlaps a gold error, once", () => {
  const gold = [span(1, 1), span(5, 6, "art.missing")];
  assertEquals(matchErrors(gold, [span(0, 1), span(1, 1)]), {
    matched: 1,
    sameTag: 1,
  });
  assertEquals(matchErrors(gold, [span(6, 8, "art.missing"), span(2, 4)]), {
    matched: 1,
    sameTag: 1,
  });
  assertEquals(matchErrors(gold, []), { matched: 0, sameTag: 0 });
});

Deno.test("detection, EFC and outcome against the gold", () => {
  const score = scoreSpeaking("m", [
    result(),
    result({
      id: "sa02",
      expected: { errors: [], clauses: 2, efc: 1, outcome: "partial" },
      errors: [],
      efc: 1,
      outcome: "done",
    }),
  ]);
  // 2 of 3 marks hit, 2 of 2 gold errors found.
  assertAlmostEquals(score.errorPrecision, 2 / 3);
  assertEquals(score.errorRecall, 1);
  assertAlmostEquals(score.errorF1, 0.8);
  assertEquals(score.tagAgreement, 0.5);
  assertEquals(score.efcMedianDiff, 0.125);
  assertEquals(score.outcomeAgreement, 0.5);
  assertEquals(score.failures, 0);
  assertEquals(score.tokensPerCase, 1900);
  assertEquals(score.passes, { errorF1: true, efc: false, outcome: false });
});

Deno.test("a failed call misses its gold errors and outcome", () => {
  const score = scoreSpeaking("m", [
    result({
      code: "llm_failed",
      errors: undefined,
      efc: undefined,
      outcome: undefined,
      calls: [{ ...call, stopReason: "server" }],
    }),
  ]);
  assertEquals(score.failures, 1);
  assertEquals(score.errorRecall, 0);
  assertEquals(score.errorF1, 0);
  assertEquals(score.efcMedianDiff, 1);
  assertEquals(score.outcomeAgreement, 0);
  assertEquals(score.schemaValid, 0);
});

Deno.test("no clauses is the largest EFC difference", () => {
  assertEquals(scoreSpeaking("m", [result({ efc: null })]).efcMedianDiff, 1);
  assertEquals(scoreSpeaking("m", []).efcMedianDiff, 1);
});
