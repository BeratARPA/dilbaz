import { assert, assertEquals } from "@std/assert";
import { lexiconFor } from "./index.ts";
import {
  aboveLevel,
  type LevelData,
  Lexicon,
  scaleOf,
  words,
} from "./levels.ts";

const data: LevelData = {
  pack: "zz@1",
  lemmas: { A1: "bada kolu see", A2: "sima", B1: "dero", B2: "lumo saw" },
  forms: "badan bada|saw saw/see|deros dero|lumos lumo",
};
const lexicon = new Lexicon(data);

Deno.test("a word takes the lowest level of its lemmas", () => {
  assertEquals(lexicon.levelOf("bada"), scaleOf("A1"));
  assertEquals(lexicon.levelOf("Badan"), scaleOf("A1"));
  // "saw" is a B2 noun and a form of the A1 verb "see".
  assertEquals(lexicon.levelOf("saw"), scaleOf("A1"));
  assertEquals(lexicon.levelOf("deros"), scaleOf("B1"));
  assertEquals(lexicon.levelOf("Ankara"), null);
});

Deno.test("words are lowercase, without clitics or numbers", () => {
  assertEquals(words("Don't say it's 5 o'clock, I can't!"), [
    "do",
    "say",
    "it",
    "o'clock",
    "i",
    "can",
  ]);
  assertEquals(words("She’ll go."), ["she", "go"]);
});

Deno.test("above level means above the learner's level plus one", () => {
  // A0: A1 is fine, A2 and up are above.
  assertEquals(aboveLevel("Bada sima dero.", "A0", lexicon), [[
    "sima",
    "dero",
  ]]);
  // A1: up to A2.
  assertEquals(aboveLevel("Bada sima dero.", "A1", lexicon), [["dero"]]);
  // A2: up to B1.
  assertEquals(aboveLevel("Bada sima dero.", "A2", lexicon), [[]]);
});

Deno.test("it counts per sentence, each word once, unknown words not", () => {
  assertEquals(
    aboveLevel("Lumo dero lumo! Kolu bada? Ankara sima.", "A0", lexicon),
    [["lumo", "dero"], [], ["sima"]],
  );
  assertEquals(aboveLevel("", "A1", lexicon), []);
});

Deno.test("the English lexicon comes from the pack", () => {
  const en = lexiconFor("en");
  assert(en !== null);
  assertEquals(en.pack, "en@1");
  assertEquals(lexiconFor("en"), en, "built once");
  assertEquals(lexiconFor("zz"), null);
  // Everyday words are low, and their forms follow their lemmas.
  for (const word of ["the", "go", "went", "children", "was"]) {
    const level = en.levelOf(word);
    assert(level !== null && level <= scaleOf("A1"), word);
  }
  const rare = en.levelOf("notwithstanding");
  assert(rare !== null && rare >= scaleOf("B2"));
});
