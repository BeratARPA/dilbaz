import { assert, assertEquals } from "@std/assert";
import { dirname, fromFileUrl, join } from "@std/path";
import {
  answerCheckSystemPrompt,
  answerCheckUserMessage,
} from "../supabase/functions/_shared/prompts/answer_check.ts";
import { catalogs } from "../supabase/functions/_shared/catalogs/index.ts";
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
