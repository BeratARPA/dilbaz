import { assert, assertEquals, assertFalse } from "@std/assert";
import { catalogs } from "../catalogs/index.ts";
import { leaks } from "../leak.ts";
import { annotateKitFor } from "../../tutor/speaking_annotate.ts";
import {
  exampleTranscripts,
  exampleWords,
  speakingAnnotatePromptVersion,
  speakingAnnotateSystemPrompt,
  speakingAnnotateUserMessage,
  speakingCategories,
  speakingExamples,
  transcriptOf,
} from "./speaking_annotate.ts";

const catalog = catalogs["tr-en"];
const system = speakingAnnotateSystemPrompt(catalog);
const kit = annotateKitFor("tr-en")!;

Deno.test("the system prompt is fixed for a catalog (cacheable)", () => {
  assertEquals(speakingAnnotateSystemPrompt(catalog), system);
  assertEquals(speakingAnnotatePromptVersion, "speaking_annotate@1");
  assertFalse(/\d{4}-\d{2}-\d{2}/.test(system), "no dates");
  assert(system.includes(`# Tag catalog (${catalog.pack})`));
});

Deno.test("it lists the speaking tags and every grammar code", () => {
  for (const tag of catalog.errorTags) {
    assertEquals(
      system.includes(`\n${tag.code}: `),
      speakingCategories.includes(tag.category),
      tag.code,
    );
  }
  for (const code of Object.keys(catalog.ruleNotes)) {
    assert(system.includes(`\n${code}: `), code);
  }
});

Deno.test("the model reads indexed words, without their times", () => {
  const words = [
    { i: 0, w: "i", start_ms: 0, end_ms: 200 },
    { i: 1, w: "go", start_ms: 300, end_ms: 500 },
  ];
  assertEquals(transcriptOf(words), "[0]i [1]go");
  const message = JSON.parse(speakingAnnotateUserMessage({
    ctx: { l1: "tr", l2: "en", level: "A1", explain_in: "l1" },
    task: { prompt_l1: "Anlat.", goal: "Tell.", can_do_codes: ["cd.x.a1"] },
    words,
  }));
  assertEquals(message, {
    ctx: { l1: "tr", l2: "en", level: "A1", explain_in: "l1" },
    task: { prompt_l1: "Anlat.", goal: "Tell." },
    words: "[0]i [1]go",
  });
});

Deno.test("every example is a valid, consistent answer", () => {
  for (const [index, example] of speakingExamples.entries()) {
    const label = exampleTranscripts[index];
    const parsed = kit.wire.safeParse(example.output);
    assert(parsed.success, label);
    const last = exampleWords[index].length - 1;
    const { clauses, errors, fillers, repairs, structures_used } =
      example.output;
    // Clauses cover every word, in order, without overlap.
    let next = 0;
    let unit = 0;
    for (const clause of clauses) {
      assertEquals(clause.start_i, next, label);
      assert(clause.end_i >= clause.start_i, label);
      assert(clause.as_unit >= unit, label);
      unit = clause.as_unit;
      next = clause.end_i + 1;
      const marked = errors.some((e) =>
        clause.start_i <= e.start_i && e.start_i <= clause.end_i
      );
      assertEquals(clause.error_free, !marked, label);
    }
    assertEquals(next, last + 1, label);
    for (const span of [...errors, ...repairs, ...structures_used]) {
      assert(span.start_i <= span.end_i && span.end_i <= last, label);
    }
    for (const filler of fillers) assert(filler.i <= last, label);
    assert(example.output.strengths.length <= 2, label);
    assert(example.output.corrections.length <= 5, label);
    // The hints never give the correction away (I-02).
    for (const correction of example.output.corrections) {
      for (const hint of Object.values(correction.ladder)) {
        assertFalse(
          leaks(hint, {
            response: correction.original,
            correction: correction.corrected,
            reference: correction.corrected,
            targetSpan: "",
            ruleNotes: [],
          }),
          `${label}: ${hint}`,
        );
      }
    }
  }
});
