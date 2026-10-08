import { assert, assertEquals, assertFalse } from "@std/assert";
import { lexiconFor } from "../levels/index.ts";
import { aboveLevel } from "../levels/levels.ts";
import {
  type GapSuggestInput,
  gapSuggestWire,
} from "../schemas/gap_suggest.ts";
import {
  exampleTexts,
  gapSuggestPromptVersion,
  gapSuggestSystemPrompt,
  gapSuggestUserMessage,
} from "./gap_suggest.ts";

const system = gapSuggestSystemPrompt();

Deno.test("the system prompt is fixed (cacheable)", () => {
  assertEquals(gapSuggestSystemPrompt(), system);
  assertEquals(gapSuggestPromptVersion, "gap_suggest@1");
  assertFalse(/\d{4}-\d{2}-\d{2}/.test(system), "no dates");
  assert(system.includes("# Simplify"));
});

Deno.test("its examples keep the contract and the level rule", () => {
  const lexicon = lexiconFor("en")!;
  const blocks = system.split("Input: ").slice(1);
  assertEquals(blocks.length, exampleTexts.length);
  let simplified = 0;
  for (const block of blocks) {
    const [inputLine, outputLine] = block.split("\nOutput: ");
    const input = JSON.parse(inputLine);
    const output = gapSuggestWire.parse(JSON.parse(outputLine.split("\n")[0]));
    const chunk = output.key_chunk.text.toLowerCase();
    assert(
      output.l2_natural.toLowerCase().includes(chunk) ||
        output.l2_simple.toLowerCase().includes(chunk),
      `${chunk} is copied from the answer`,
    );
    for (
      const words of aboveLevel(output.l2_simple, input.ctx.level, lexicon)
    ) {
      assert(words.length <= 1, `${output.l2_simple}: ${words}`);
    }
    if (input.simplify) {
      simplified++;
      for (const word of input.simplify.above_level) {
        assertFalse(output.l2_simple.toLowerCase().includes(word), word);
      }
    }
    assert(output.notes_l1.split(/\s+/).length <= 20, output.notes_l1);
  }
  assertEquals(simplified, 1, "one example simplifies");
});

Deno.test("the user message has a fixed shape without empty extras", () => {
  const input: GapSuggestInput = {
    ctx: { l1: "tr", l2: "en", level: "A1", explain_in: "l1" },
    l1_text: "Yarın görüşürüz.",
    context: "daily",
  };
  assertEquals(
    gapSuggestUserMessage(input),
    '{"ctx":{"l1":"tr","l2":"en","level":"A1","explain_in":"l1"},' +
      '"l1_text":"Yarın görüşürüz.","context":"daily"}',
  );
  const withAll = gapSuggestUserMessage(
    { ...input, note: "işte" },
    { previous: "See you tomorrow.", above_level: ["tomorrow"] },
  );
  assertEquals(JSON.parse(withAll).note, "işte");
  assertEquals(JSON.parse(withAll).simplify, {
    previous: "See you tomorrow.",
    above_level: ["tomorrow"],
  });
});
