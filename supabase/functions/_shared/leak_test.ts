import { assert, assertEquals } from "@std/assert";
import { type LeakContext, leaks, words } from "./leak.ts";

Deno.test("words are lowercase letters and digits; apostrophes split", () => {
  assertEquals(words("'Went'i kullan, 2 kez!"), [
    "went",
    "i",
    "kullan",
    "2",
    "kez",
  ]);
  assertEquals(words("  "), []);
});

const past: LeakContext = {
  response: "I go to school yesterday",
  correction: "I went to school yesterday.",
  reference: "I went to school yesterday.",
  targetSpan: "went",
  ruleNotes: [
    "Düzensiz fiillerin geçmiş hâli ezberlenir: go → went, see → saw.",
  ],
};

Deno.test("a hint may not name the corrected target word", () => {
  assert(leaks("'went' kullan.", past));
  assert(leaks("Doğru biçim: Went'i dene.", past), "with a Turkish suffix");
  assert(!leaks("'go' kelimesinin geçmiş hâlini kullan.", past));
  assert(!leaks("Fiilin zamanı yanlış.", past));
});

Deno.test("words of the card's rule notes are allowed", () => {
  const be: LeakContext = {
    response: "I very happy",
    correction: "I am very happy.",
    reference: "I am very happy.",
    targetSpan: "I am very happy",
    ruleNotes: [
      "Cümlede be olmalı: I ile am, he/she/it ile is, you/we/they ile are.",
    ],
  };
  assert(!leaks("Fiil yoksa be gerekir: I ile am, he/she/it ile is.", be));
  // Without the note, "am" would be the corrected word itself.
  assert(leaks("I ile am kullan.", { ...be, ruleNotes: [] }));
});

Deno.test("a hint may not hold the whole answer or the target phrase", () => {
  const breakfast: LeakContext = {
    response: "breakfast have they now",
    correction: "They have breakfast now.",
    reference: "They are having breakfast now.",
    targetSpan: "have breakfast",
    ruleNotes: [],
  };
  // Every word was said, but not in this order.
  assert(leaks("Şöyle de: have breakfast.", breakfast));
  assert(leaks("Doğrusu: They have breakfast now.", breakfast));
  assert(!leaks("'have' kelimesinin yerine bak.", breakfast));
});

Deno.test("single letters and the learner's own words never count", () => {
  const article: LeakContext = {
    response: "my sister is teacher",
    correction: "My sister is a teacher.",
    reference: "My sister is a teacher.",
    targetSpan: "sister",
    ruleNotes: [],
  };
  assert(!leaks("'teacher' kelimesinden önce a ya da an gelir.", article));
  assert(!leaks("", article));
});
