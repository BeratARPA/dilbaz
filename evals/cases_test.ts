import { assert, assertEquals } from "@std/assert";
import { dirname, fromFileUrl, join } from "@std/path";
import {
  answerCheckSystemPrompt,
  answerCheckUserMessage,
} from "../supabase/functions/_shared/prompts/answer_check.ts";
import { catalogs } from "../supabase/functions/_shared/catalogs/index.ts";
import { exampleTexts } from "../supabase/functions/_shared/prompts/gap_suggest.ts";
import {
  gapContexts,
  GapSuggestInput,
} from "../supabase/functions/_shared/schemas/gap_suggest.ts";
import {
  answerCheckCategories,
  AnswerCheckInput,
  verdicts,
} from "../supabase/functions/_shared/schemas/answer_check.ts";

const here = dirname(fromFileUrl(import.meta.url));
const cases = (await Deno.readTextFile(
  join(here, "tutor", "answer_check", "cases.jsonl"),
)).split("\n").filter((line) => line.trim() !== "").map((line) =>
  JSON.parse(line)
);

Deno.test("the answer_check gold set has at least 200 cases (docs/07 §8)", () => {
  assert(cases.length >= 200, `${cases.length}`);
  assertEquals(new Set(cases.map((c) => c.id)).size, cases.length);
});

Deno.test("every case is what the app would send, with a gold answer", () => {
  const catalog = catalogs["tr-en"];
  const tags = new Set(
    catalog.errorTags
      .filter((t) => answerCheckCategories.includes(t.category))
      .map((t) => t.code),
  );
  for (const c of cases) {
    const input = AnswerCheckInput.parse(c.input);
    assert(input.response.text.trim() !== "", c.id);
    assert(answerCheckUserMessage(input).length < 4000, c.id);
    assert(c.expected.verdicts.length > 0, c.id);
    for (const v of c.expected.verdicts) {
      assert((verdicts as readonly string[]).includes(v), `${c.id}: ${v}`);
    }
    for (const t of c.expected.tags) assert(tags.has(t), `${c.id}: ${t}`);
  }
});

Deno.test("no case reuses a sentence of the prompt's examples", () => {
  const system = answerCheckSystemPrompt(catalogs["tr-en"]);
  const shown = [...system.matchAll(/"reference_l2":"([^"]+)"/g)].map((m) =>
    m[1]
  );
  assertEquals(shown.length, 10);
  for (const c of cases) {
    assert(!shown.includes(c.input.item.reference_l2), c.id);
  }
});

Deno.test("the evals use the functions' imports", async () => {
  const own = JSON.parse(await Deno.readTextFile(join(here, "deno.json")));
  const functions = JSON.parse(
    await Deno.readTextFile(
      join(here, "..", "supabase", "functions", "deno.json"),
    ),
  );
  assertEquals(own.imports, functions.imports);
});

const gapCases = (await Deno.readTextFile(
  join(here, "tutor", "gap_suggest", "cases.jsonl"),
)).split("\n").filter((line) => line.trim() !== "").map((line) =>
  JSON.parse(line)
);

Deno.test("the gap_suggest set covers the levels and the contexts", () => {
  assert(gapCases.length >= 40, `${gapCases.length}`);
  assertEquals(new Set(gapCases.map((c) => c.id)).size, gapCases.length);
  const inputs = gapCases.map((c) => GapSuggestInput.parse(c.input));
  for (const [index, input] of inputs.entries()) {
    const id = gapCases[index].id;
    assert(input.l1_text.trim() !== "", id);
    assert(gapCases[index].reference.trim() !== "", id);
    // The level's scaffolds: Turkish notes up to A2.
    const a = ["A0", "A1", "A2"].includes(input.ctx.level);
    assertEquals(input.ctx.explain_in, a ? "l1" : "l2", id);
  }
  assertEquals(
    new Set(inputs.map((i) => i.context)),
    new Set(gapContexts),
  );
  assertEquals(
    new Set(inputs.map((i) => i.ctx.level)),
    new Set(["A0", "A1", "A2", "B1"]),
  );
});

Deno.test("no gap_suggest case reuses a text of the prompt's examples", () => {
  const shown = new Set(exampleTexts);
  for (const c of gapCases) assert(!shown.has(c.input.l1_text), c.id);
});
