import { assert, assertEquals } from "@std/assert";
import { referenceWords } from "../_shared/prompts/pron_check.ts";
import type {
  PronCheckInput,
  PronCheckWire,
} from "../_shared/schemas/pron_check.ts";
import {
  maxIssues,
  parsePronWire,
  pronKitFor,
  pronOutput,
} from "./pron_check.ts";

const kit = pronKitFor("tr-en")!;
const served = { provider: "gemini", model: "gemini-3.1-flash-lite" };
const input: PronCheckInput = {
  ctx: { l1: "tr", l2: "en", level: "A1", explain_in: "l1" },
  reference: 'I think it\'s "three", not two.',
  audio: { data: "AAAA", mime_type: "audio/wav" },
};

Deno.test("the sentence is numbered without its punctuation", () => {
  assertEquals(referenceWords(input.reference), [
    "I",
    "think",
    "it's",
    "three",
    "not",
    "two",
  ]);
});

Deno.test("the kit knows the pair's pronunciation tags only", () => {
  assert(kit.system.includes("phon.th"));
  assert(!kit.system.includes("perc.endings"));
  assertEquals(pronKitFor("tr-de"), null);
  assertEquals(pronKitFor("tr-en"), kit);
});

Deno.test("an answer outside the closed list is no answer (I-11)", () => {
  const valid: PronCheckWire = {
    uncertain: false,
    words: [],
    issues: [{ i: 1, tag: "phon.th", heard: "tink" }],
  };
  assertEquals(parsePronWire(kit, JSON.stringify(valid)), valid);
  assertEquals(
    parsePronWire(
      kit,
      JSON.stringify({
        ...valid,
        issues: [{ i: 1, tag: "pron.r", heard: "" }],
      }),
    ),
    null,
  );
  assertEquals(parsePronWire(kit, "{"), null);
  assertEquals(parsePronWire(kit, JSON.stringify({ issues: [] })), null);
});

Deno.test("the server keeps indices inside, one tag per word, nothing when uncertain", () => {
  const output = pronOutput(
    input,
    {
      uncertain: false,
      words: [],
      issues: [
        { i: 1, tag: "phon.th", heard: "  tink " },
        { i: 1, tag: "phon.th", heard: "sink" },
        { i: 3, tag: "phon.th", heard: "tree" },
        { i: 3, tag: "phon.vowel_length", heard: "x".repeat(80) },
        { i: 9, tag: "phon.w_v", heard: "vat" },
      ],
    },
    kit,
    served,
  );
  assertEquals(output.issues.map((issue) => [issue.word, issue.tag]), [
    ["think", "phon.th"],
    ["three", "phon.th"],
    ["three", "phon.vowel_length"],
  ]);
  assertEquals(output.issues[0].heard, "tink");
  assertEquals(output.issues[2].heard.length, 40);
  assertEquals(output.model, served.model);

  const many = pronOutput(
    input,
    {
      uncertain: false,
      words: [],
      issues: Array.from({ length: 6 }, (_, i) => [
        { i, tag: "phon.th", heard: "" },
        { i, tag: "phon.w_v", heard: "" },
      ]).flat(),
    },
    kit,
    served,
  );
  assertEquals(many.issues.length, maxIssues);

  const unsure = pronOutput(
    input,
    {
      uncertain: true,
      words: [],
      issues: [{ i: 1, tag: "phon.th", heard: "tink" }],
    },
    kit,
    served,
  );
  assertEquals(unsure, { ...unsure, uncertain: true, issues: [] });
});
