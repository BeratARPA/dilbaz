import { assert, assertEquals } from "@std/assert";
import { Lexicon } from "../_shared/levels/levels.ts";
import type {
  GapSuggestInput,
  GapSuggestWire,
} from "../_shared/schemas/gap_suggest.ts";
import { gapKitFor, gapOutput, parseGapWire, tooHard } from "./gap_suggest.ts";

const lexicon = new Lexicon({
  pack: "zz@1",
  lemmas: { A1: "i want go out tonight", B1: "rather", B2: "venture" },
  forms: "going go|ventured venture",
});

const input = (level: GapSuggestInput["ctx"]["level"]): GapSuggestInput => ({
  ctx: { l1: "tr", l2: "en", level, explain_in: "l1" },
  l1_text: "Bu akşam dışarı çıkmak istiyorum.",
  context: "daily",
});

const wire = (simple: string): GapSuggestWire => ({
  l2_natural: "I'd rather venture out tonight.",
  l2_simple: simple,
  key_chunk: { text: "go out", gloss_l1: "dışarı çıkmak" },
  register: "informal",
  notes_l1: "",
});

Deno.test("the English kit has the prompt, the schema and the levels", () => {
  const kit = gapKitFor("en");
  assert(kit !== null);
  assertEquals(gapKitFor("en"), kit, "built once");
  assertEquals(kit.lexicon.pack, "en@1");
  assertEquals(gapKitFor("zz"), null);
  const schema = kit.schema as { required: string[] };
  assertEquals(schema.required, [
    "l2_natural",
    "l2_simple",
    "key_chunk",
    "register",
    "notes_l1",
  ]);
});

Deno.test("only a valid answer is accepted", () => {
  const valid = JSON.stringify(wire("I want to go out tonight."));
  assertEquals(parseGapWire(valid)?.l2_simple, "I want to go out tonight.");
  assertEquals(parseGapWire("not json"), null);
  assertEquals(parseGapWire(JSON.stringify({ ...wire("x"), extra: 1 })), null);
  assertEquals(
    parseGapWire(JSON.stringify({ ...wire("x"), register: "slang" })),
    null,
  );
  assertEquals(parseGapWire(JSON.stringify(wire("   "))), null);
});

Deno.test("more than one hard word in a sentence asks to simplify", () => {
  // A1: B1 and B2 words are above A2.
  assertEquals(
    tooHard(input("A1"), wire("I'd rather venture out."), lexicon),
    ["rather", "venture"],
  );
  // One hard word in each sentence is fine.
  assertEquals(
    tooHard(input("A1"), wire("I'd rather go. I ventured out."), lexicon),
    null,
  );
  // B1 and above are not checked.
  assertEquals(
    tooHard(input("B1"), wire("I'd rather venture out."), lexicon),
    null,
  );
});

Deno.test("the answer names its hard words, provider and model", () => {
  const output = gapOutput(
    input("A0"),
    { ...wire("I'd rather go out."), notes_l1: "" },
    lexicon,
    { simplified: true, provider: "gemini", model: "m" },
  );
  assertEquals(output.notes_l1, null);
  assertEquals(output.above_level, ["rather"]);
  assertEquals(output.simplified, true);
  assertEquals(output.key_chunk, { text: "go out", gloss_l1: "dışarı çıkmak" });
  assertEquals(
    gapOutput(input("B2"), wire("I'd rather go."), lexicon, {
      simplified: false,
      provider: "groq",
      model: "g",
    }).above_level,
    [],
  );
});
