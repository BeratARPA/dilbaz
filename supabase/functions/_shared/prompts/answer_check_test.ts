import { assert, assertEquals, assertFalse } from "@std/assert";
import { catalogs } from "../catalogs/index.ts";
import { leaks } from "../leak.ts";
import {
  answerCheckCategories,
  type AnswerCheckInput,
  answerCheckWire,
  errorVerdicts,
} from "../schemas/answer_check.ts";
import {
  answerCheckPromptVersion,
  answerCheckSystemPrompt,
  answerCheckUserMessage,
} from "./answer_check.ts";

const catalog = catalogs["tr-en"];
const system = answerCheckSystemPrompt(catalog);

Deno.test("the system prompt is fixed for a catalog (cacheable)", () => {
  assertEquals(answerCheckSystemPrompt(catalog), system);
  assertEquals(answerCheckPromptVersion, "answer_check@3");
  assertFalse(/\d{4}-\d{2}-\d{2}/.test(system), "no dates");
  assertFalse(
    /[0-9a-f]{8}-[0-9a-f]{4}-/.test(system),
    "no identifiers",
  );
  assert(system.includes(`# Error tags (${catalog.pack})`));
});

Deno.test("it lists the card tags of the catalog and no others", () => {
  for (const tag of catalog.errorTags) {
    const listed = system.includes(`- ${tag.code}:`);
    assertEquals(
      listed,
      answerCheckCategories.includes(tag.category),
      tag.code,
    );
  }
});

Deno.test("its examples keep the contract and give nothing away", () => {
  const tags = catalog.errorTags
    .filter((tag) => answerCheckCategories.includes(tag.category))
    .map((tag) => tag.code) as [string, ...string[]];
  const wire = answerCheckWire(tags);
  const blocks = system.split("Input: ").slice(1);
  assertEquals(blocks.length, 13);
  const seen = new Set<string>();
  for (const block of blocks) {
    const [inputLine, outputLine] = block.split("\nOutput: ");
    const input = JSON.parse(inputLine);
    const output = wire.parse(JSON.parse(outputLine.split("\n")[0]));
    seen.add(output.verdict);
    const needsLadder = errorVerdicts.includes(output.verdict);
    assertEquals(output.ladder.h4 !== "", needsLadder, inputLine);
    for (const hint of [output.ladder.h1, output.ladder.h2, output.ladder.h3]) {
      assertFalse(
        leaks(hint, {
          response: input.response.text,
          correction: output.ladder.h4,
          reference: input.item.reference_l2,
          targetSpan: input.item.target_span,
          ruleNotes: input.item.grammar_codes.map((code: string) =>
            catalog.ruleNotes[code] ?? ""
          ),
        }),
        hint,
      );
    }
  }
  assertEquals(seen.size, 7, "every verdict has an example");
});

Deno.test("the user message has a fixed shape without empty extras", () => {
  const input: AnswerCheckInput = {
    ctx: { l1: "tr", l2: "en", level: "A1", explain_in: "l1" },
    item: {
      key: "en.ws.work.v.1",
      prompt_l1: "O her gün çalışır.",
      reference_l2: "He works every day.",
      variants: [],
      alternatives: [],
      target_span: "works",
      grammar_codes: [],
    },
    response: { text: "he work every day", source: "asr" },
    attempt_no: 2,
    previous_responses: ["he working every day"],
  };
  assertEquals(
    answerCheckUserMessage(input),
    '{"ctx":{"l1":"tr","l2":"en","level":"A1","explain_in":"l1"},' +
      '"item":{"key":"en.ws.work.v.1","prompt_l1":"O her gün çalışır.",' +
      '"reference_l2":"He works every day.","variants":[],"alternatives":[],' +
      '"target_span":"works","grammar_codes":[]},' +
      '"response":{"text":"he work every day","source":"asr"},' +
      '"attempt_no":2,"previous_responses":["he working every day"]}',
  );
});
