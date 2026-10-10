import { assert, assertEquals } from "@std/assert";
import type {
  AnswerCheckInput,
  AnswerCheckWire,
} from "../_shared/schemas/answer_check.ts";
import { guard, kitFor, parseWire } from "./answer_check.ts";

const kit = kitFor("tr-en")!;
const served = { provider: "gemini", model: "m" };

const input: AnswerCheckInput = {
  ctx: { l1: "tr", l2: "en", level: "A1", explain_in: "l1" },
  item: {
    key: "en.ws.work.v.1",
    prompt_l1: "O her gün çalışır.",
    reference_l2: "He works every day.",
    variants: [],
    alternatives: [],
    target_span: "works",
    grammar_codes: ["gp.present_simple.affirmative"],
  },
  response: { text: "He work work every day", source: "asr" },
  attempt_no: 1,
  previous_responses: [],
};

const wrong: AnswerCheckWire = {
  verdict: "minor_error",
  target_ok: false,
  error_tags: ["agr.3sg_s", "agr.3sg_s"],
  error_spans: [
    { text: "work", tag: "agr.3sg_s" },
    { text: "WORK", tag: "agr.3sg_s" },
    { text: "sleeps", tag: "agr.3sg_s" },
    { text: "every", tag: "art.missing" },
  ],
  ladder: {
    h1: "Fiilin biçiminde küçük bir sorun var.",
    h2: "'work' kelimesine bak.",
    h3: "Doğrusu 'works' olmalı.",
    h4: "He works every day.",
  },
  variant_to_learn: "",
  confidence: 0.9,
};

Deno.test("only a pair with a catalog has a kit", () => {
  assertEquals(kit.catalog.pack, "tr-en@1");
  assertEquals(kitFor("tr-en"), kit, "built once");
  assertEquals(kitFor("tr-de"), null);
});

Deno.test("an answer outside the contract is not accepted", () => {
  assertEquals(parseWire(kit, JSON.stringify(wrong))?.verdict, "minor_error");
  assertEquals(parseWire(kit, "not json"), null);
  assertEquals(parseWire(kit, "{}"), null);
  // A tag outside the closed list (I-11), and a card answer's
  // pronunciation tag.
  for (const tag of ["grammar.other", "phon.th"]) {
    assertEquals(
      parseWire(kit, JSON.stringify({ ...wrong, error_tags: [tag] })),
      null,
      tag,
    );
  }
  assertEquals(
    parseWire(kit, JSON.stringify({ ...wrong, extra: 1 })),
    null,
    "no extra fields",
  );
  assertEquals(
    parseWire(
      kit,
      JSON.stringify({ ...wrong, ladder: { ...wrong.ladder, h4: " " } }),
    ),
    null,
    "a ladder needs its corrected sentence",
  );
  assertEquals(
    parseWire(kit, JSON.stringify({ ...wrong, confidence: 1.5 })),
    null,
  );
});

Deno.test("a hint that gives the answer away is left to the templates", () => {
  const { output, leaked } = guard(input, wrong, kit, served);

  assertEquals(leaked, ["h3"]);
  assertEquals(output.ladder, {
    h1: "Fiilin biçiminde küçük bir sorun var.",
    h2: "'work' kelimesine bak.",
    h3: "",
    h4: "He works every day.",
  });
  assertEquals(output.error_tags, ["agr.3sg_s"]);
  // Quoted words become ranges, left to right; words not in the answer
  // and tags not given for it are dropped.
  assertEquals(output.error_spans, [
    { start: 3, end: 7, tag: "agr.3sg_s" },
    { start: 8, end: 12, tag: "agr.3sg_s" },
  ]);
  assertEquals(output.variant_to_learn, null);
  assertEquals(output.catalog, "tr-en@1");
  assertEquals(output.model, "m");
});

Deno.test("answers that need no ladder get none", () => {
  const correct = guard(
    input,
    {
      ...wrong,
      verdict: "correct",
      target_ok: false,
    },
    kit,
    served,
  ).output;
  assertEquals(correct.target_ok, true);
  assertEquals(correct.error_tags, []);
  assertEquals(correct.error_spans, []);
  assertEquals(correct.ladder, { h1: "", h2: "", h3: "", h4: "" });

  const variant = guard(
    input,
    {
      ...wrong,
      verdict: "acceptable_variant",
      target_ok: false,
    },
    kit,
    served,
  ).output;
  assertEquals(variant.target_ok, false);
  assertEquals(variant.variant_to_learn, "He work work every day");
  assertEquals(variant.ladder.h4, "");
});

Deno.test("wrong and off-target answers never pass the target", () => {
  for (const verdict of ["wrong", "off_target"] as const) {
    const { output } = guard(
      input,
      {
        ...wrong,
        verdict,
        target_ok: true,
      },
      kit,
      served,
    );
    assertEquals(output.target_ok, false, verdict);
  }
  const offTarget = guard(
    input,
    { ...wrong, verdict: "off_target" },
    kit,
    served,
  );
  assertEquals(offTarget.output.error_tags, [], "only errors carry tags");
});

Deno.test("only speech can be unintelligible", () => {
  const spoken = guard(
    input,
    { ...wrong, verdict: "unintelligible" },
    kit,
    served,
  );
  assertEquals(spoken.output.verdict, "unintelligible");
  assertEquals(spoken.output.ladder.h4, "");

  const typed = guard(
    { ...input, response: { text: "asdkjh", source: "typed" } },
    { ...wrong, verdict: "unintelligible" },
    kit,
    served,
  );
  assertEquals(typed.output.verdict, "off_target");
  assert(typed.output.ladder.h4 !== "");
});
