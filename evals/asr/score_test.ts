import { assert, assertAlmostEquals, assertEquals } from "@std/assert";
import {
  fillersOf,
  keepsError,
  says,
  scoreAsr,
  type ScriptedItem,
  wer,
  words,
} from "./score.ts";

const goes: ScriptedItem = {
  id: "s01",
  text: "He go to work every day.",
  keep: ["he go"],
  fix: ["he goes"],
};

Deno.test("words are lowercase, without punctuation, contractions whole", () => {
  assertEquals(words("I didn't GO, there… ‘ok’"), [
    "i",
    "didn't",
    "go",
    "there",
    "ok",
  ]);
});

Deno.test("a phrase is said only as whole words in order", () => {
  assert(says("Well, he go to work.", "he go"));
  assert(!says("he goes to work", "he go"));
  assert(!says("go he", "he go"));
});

Deno.test("an error is kept only as said, never corrected", () => {
  assert(keepsError(goes, "He go to work every day."));
  assert(!keepsError(goes, "He goes to work every day."));
  // Lost: the words around the error are gone.
  assert(!keepsError(goes, "go to work every day"));
  const two: ScriptedItem = {
    id: "s02",
    text: "She have two brother.",
    keep: ["she have", "two brother"],
    fix: ["she has", "two brothers"],
  };
  assert(!keepsError(two, "She have two brothers."), "half kept is lost");
});

Deno.test("word error rate counts the edits against the reference", () => {
  assertEquals(wer("he go to work", "he go to work"), 0);
  assertEquals(wer("he go to work", "he goes to work"), 0.25);
  assertEquals(wer("he go to work", "he go work today"), 0.5);
  assertEquals(wer("", ""), 0);
  assertEquals(wer("", "noise"), 1);
});

Deno.test("fillers are found as words", () => {
  assertEquals(fillersOf("Um, I go, uh, to the... hmm, cinema"), [
    "um",
    "uh",
    "hmm",
  ]);
});

Deno.test("the score: errors kept, failures, WER, fillers, latency", () => {
  const score = scoreAsr(
    "fake",
    [goes, { ...goes, id: "s02" }, { ...goes, id: "s03" }],
    [
      {
        id: "s01",
        candidate: "fake",
        text: "He go to work every day",
        latencyMs: 100,
      },
      {
        id: "s02",
        candidate: "fake",
        text: "He goes to work every day",
        latencyMs: 300,
      },
      { id: "s03", candidate: "fake", failure: "network" },
      { id: "f01", candidate: "fake", text: "um I like it", latencyMs: 200 },
    ],
    new Map([["f01", "um uh I like it"]]),
  );
  assertAlmostEquals(score.errorKept, 1 / 3);
  assertEquals(score.errorLost, ["s02", "s03"]);
  assertEquals(score.failures, 1);
  assertEquals(score.passes.errorKept, false);
  assertAlmostEquals(score.werFree!, 1 / 5);
  assertEquals(score.fillerCapture, 0.5);
  assertEquals(score.latencyP50, 200);
});
