import { assertEquals } from "@std/assert";
import { type PronCase, type PronResult, scorePron } from "./score.ts";

const cases: PronCase[] = [
  { id: "a", text: "We work.", i: 1, expect: { i: 1, tag: "phon.w_v" } },
  { id: "a-clean", text: "We work.", i: 1, expect: null },
  { id: "b", text: "I think.", i: 1, expect: { i: 1, tag: "phon.th" } },
  { id: "b-clean", text: "I think.", i: 1, expect: null },
];

const said = (
  id: string,
  issues: [number, string][],
  more: Partial<PronResult> = {},
): PronResult => ({
  id,
  model: "m",
  uncertain: false,
  issues: issues.map(([i, tag]) => ({ i, tag, heard: "" })),
  ...more,
});

Deno.test("found on its word with its tag; right sentences stay quiet", () => {
  const score = scorePron(cases, [
    said("a", [[1, "phon.w_v"]], { latencyMs: 900 }),
    said("a-clean", [], { latencyMs: 700 }),
    said("b", [[1, "phon.th"], [0, "phon.vowel_length"]], { latencyMs: 800 }),
    said("b-clean", []),
  ]);
  assertEquals(score.found, 1);
  assertEquals(score.falseAlarm, 0);
  assertEquals(score.strayPerCase, 0.5);
  assertEquals(score.byTag, { "phon.w_v": 1, "phon.th": 1 });
  assertEquals(score.medianLatencyMs, 800);
  assertEquals(score.passes, true);
});

Deno.test("a wrong tag is on the word but not found; alarms fail it", () => {
  const score = scorePron(cases, [
    said("a", [[1, "phon.th"]]),
    said("a-clean", [[1, "phon.w_v"]]),
    said("b", [], { uncertain: true }),
    { id: "b-clean", model: "m", failure: "quota" },
  ]);
  assertEquals(score.found, 0);
  assertEquals(score.onWord, 0.5);
  assertEquals(score.falseAlarm, 1);
  assertEquals(score.uncertain, 0.333);
  assertEquals(score.failed, 1);
  assertEquals(score.passes, false);
});

Deno.test("nothing answered scores nothing and does not pass", () => {
  const score = scorePron(cases, []);
  assertEquals(score.answered, 0);
  assertEquals(score.medianLatencyMs, null);
  assertEquals(score.passes, false);
});
