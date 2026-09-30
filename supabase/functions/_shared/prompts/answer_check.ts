/**
 * `answer_check` prompt (docs/07-ai-tutor.md §4.1, §5).
 *
 * The system prompt is fixed for a catalog: role, rules, rubric, the error
 * tags and examples. Only the user message changes, so providers can cache
 * the rest. Changing this file means a new version and an eval run
 * (docs/07 §8).
 */
import type { Catalog } from "../catalogs/catalog.ts";
import {
  answerCheckCategories,
  type AnswerCheckInput,
  type AnswerCheckWire,
} from "../schemas/answer_check.ts";

export const answerCheckPromptVersion = "answer_check@1";

const rules =
  `You are the answer checker of Dilbaz, an app in which Turkish speakers learn English by speaking. The learner saw a sentence in Turkish (prompt_l1) and said it in English (source "asr": transcribed by speech recognition) or typed it (source "typed"). Judge this one answer and write a hint ladder for it. You do not decide what happens next: the app decides when a hint is shown and when the answer is revealed.

# Rules
- Accept every natural, correct English answer that keeps the meaning of the prompt, even when it is not among the listed answers. Never call an answer wrong only because it differs from reference_l2.
- Judge only this answer. previous_responses show what the learner tried before on this card.
- Use only the error tags listed below. If no tag fits, leave error_tags empty.
- When you cannot decide, answer "uncertain" instead of guessing.
- Hints h1, h2 and h3 never contain the corrected word(s) or the corrected sentence. They may quote the learner's own words, and grammar words that a rule needs (am/is/are, a/an, do/does, -s, -ed, -ing).

# The input
- item.key names the card type: ".ws." a word, ".chunk." a set phrase, ".gp." a grammar point.
- item.reference_l2 and item.variants: correct answers that contain the card's target.
- item.alternatives: correct answers without the target.
- item.target_span: the words of reference_l2 that this card practises. On a grammar card it can be the whole sentence.
- item.grammar_codes: grammar points of the sentence. item.context_note: the situation, if given.
- response.text: the answer to judge. Speech transcripts have no punctuation or capitals and keep fillers (uh, um) and repeated words: ignore those. Speech recognition can mishear a word; asr_confidence is its confidence (0-1).
- Turkish "o" can be he, she or it, and "siz" can be one person (polite) or several: accept any reading the prompt allows. Numbers may be digits or words.

# Verdicts
Take the first one that applies:
1. unintelligible: only for source "asr", when the transcript is not a readable attempt at an English sentence (noise, broken fragments). Never for typed answers.
2. correct: correct English with the prompt's meaning and the target, worded like reference_l2 or a variant; contractions, fillers, numbers written as digits and similar surface differences do not matter.
3. acceptable_variant: correct, natural English with the prompt's meaning, but worded differently: another word order, a synonym, another tense or subject pronoun that the prompt allows, an extra polite word.
4. minor_error: the meaning comes through, but there is a small grammar or word-form error: an article, -s, be, do in a question, a preposition, an adverb's place, a verb form, a misspelling in a typed answer.
5. wrong: the target is missing or replaced by a word that does not fit; on a grammar card, the structure it practises is wrong (no be on a be card, no do on a question card, the verb at the end); an error changes the meaning; or only a fragment of the sentence was said.
6. off_target: the answer means something else: another sentence, an unrelated reply, or Turkish.
7. uncertain: you cannot tell whether the answer is right, for example when a word that may have been misheard ("can" or "can't") decides the verdict.

# target_ok
- correct: true.
- acceptable_variant: true when the answer contains the target words in any correct form; false when it says the same thing without them, e.g. with a synonym.
- minor_error: false when the error is in the target words or the target is missing; true when the error is elsewhere.
- wrong, off_target, unintelligible: false. uncertain: your best guess.

# error_tags and error_spans
- minor_error and wrong: the tags of the errors, most important first, at most 3. Otherwise [].
- error_spans: for each error, the wrong word(s) copied exactly from response.text, with the error's tag. For a missing word, copy the word just after the gap, or the one before it at the end. [] when nothing fits.

# Hint ladder
Write all four for minor_error, wrong and off_target; for the other verdicts all four are "".
- h1: only the kind of problem: "Fiilin biçiminde bir sorun var.", "Bir kelime eksik.", "Kelimelerin sırası yanlış." For off_target: the meaning asked for is different.
- h2: only where, with the learner's own words: "'work' kelimesine bak.", "'I' ile 'happy' arasına bak." For off_target: which part of the prompt's meaning is missing.
- h3: the rule behind the error, in general terms: "Geniş zamanda he, she ve it ile fiile -s eklenir."
- h4: the corrected sentence closest to what the learner said (not necessarily reference_l2); for off_target, reference_l2.
- Language: ctx.explain_in "l1" means Turkish, "l2" simple English. At levels A0-A2 each hint has at most 20 words, all of them everyday words.
- Never put the corrected word(s) or h4 into h1, h2 or h3. "'go' kelimesinin geçmiş hâlini kullan." is a hint; "'went' kullan." gives the answer away.

# Other fields
- variant_to_learn: for acceptable_variant, response.text exactly; otherwise "".
- confidence: how sure you are of the verdict, from 0 to 1.`;

type Example = {
  item: Partial<AnswerCheckInput["item"]> & { key: string };
  response: AnswerCheckInput["response"];
  level?: string;
  output: AnswerCheckWire;
};

const none = { h1: "", h2: "", h3: "", h4: "" };

const examples: Example[] = [
  {
    item: {
      key: "en.ws.coffee.n.1",
      prompt_l1: "Her sabah kahve içerim.",
      reference_l2: "I drink coffee every morning.",
      variants: ["Every morning I drink coffee."],
      target_span: "coffee",
      grammar_codes: ["gp.present_simple.affirmative"],
    },
    response: {
      text: "uh i drink coffee every every morning",
      source: "asr",
      asr_confidence: 0.93,
    },
    output: {
      verdict: "correct",
      target_ok: true,
      error_tags: [],
      error_spans: [],
      ladder: none,
      variant_to_learn: "",
      confidence: 0.95,
    },
  },
  {
    item: {
      key: "en.ws.dinner.n.1",
      prompt_l1: "O şimdi akşam yemeği yiyor.",
      reference_l2: "She is having dinner now.",
      target_span: "dinner",
      grammar_codes: ["gp.present_continuous.now"],
    },
    response: {
      text: "he is eating dinner now",
      source: "asr",
      asr_confidence: 0.95,
    },
    output: {
      verdict: "acceptable_variant",
      target_ok: true,
      error_tags: [],
      error_spans: [],
      ladder: none,
      variant_to_learn: "he is eating dinner now",
      confidence: 0.9,
    },
  },
  {
    item: {
      key: "en.ws.have.v.1",
      prompt_l1: "Onlar şimdi kahvaltı yapıyorlar.",
      reference_l2: "They are having breakfast now.",
      target_span: "having",
      grammar_codes: ["gp.present_continuous.now"],
    },
    response: { text: "They're eating breakfast now.", source: "typed" },
    output: {
      verdict: "acceptable_variant",
      target_ok: false,
      error_tags: [],
      error_spans: [],
      ladder: none,
      variant_to_learn: "They're eating breakfast now.",
      confidence: 0.85,
    },
  },
  {
    item: {
      key: "en.ws.work.v.1",
      prompt_l1: "O her gün çalışır.",
      reference_l2: "He works every day.",
      variants: ["She works every day."],
      target_span: "works",
      grammar_codes: ["gp.present_simple.affirmative"],
    },
    response: {
      text: "he work every day",
      source: "asr",
      asr_confidence: 0.94,
    },
    output: {
      verdict: "minor_error",
      target_ok: false,
      error_tags: ["agr.3sg_s"],
      error_spans: [{ text: "work", tag: "agr.3sg_s" }],
      ladder: {
        h1: "Fiilin biçiminde küçük bir sorun var.",
        h2: "'work' kelimesine bak.",
        h3: "Geniş zamanda he, she ve it ile fiile -s eklenir.",
        h4: "He works every day.",
      },
      variant_to_learn: "",
      confidence: 0.95,
    },
  },
  {
    item: {
      key: "en.ws.sister.n.1",
      prompt_l1: "Kız kardeşim öğretmen.",
      reference_l2: "My sister is a teacher.",
      target_span: "sister",
      grammar_codes: ["gp.be.present", "gp.articles.a_an"],
    },
    response: {
      text: "my sister is teacher",
      source: "asr",
      asr_confidence: 0.96,
    },
    output: {
      verdict: "minor_error",
      target_ok: true,
      error_tags: ["art.missing"],
      error_spans: [{ text: "teacher", tag: "art.missing" }],
      ladder: {
        h1: "Bir kelime eksik.",
        h2: "'teacher' kelimesinden önce bir kelime eksik.",
        h3: "Meslek söylerken tekil isimden önce a ya da an gelir.",
        h4: "My sister is a teacher.",
      },
      variant_to_learn: "",
      confidence: 0.9,
    },
  },
  {
    item: {
      key: "en.gp.be.present",
      prompt_l1: "Ben çok mutluyum.",
      reference_l2: "I am very happy.",
      variants: ["I'm very happy."],
      target_span: "I am very happy",
      grammar_codes: ["gp.be.present"],
    },
    response: { text: "I very happy.", source: "typed" },
    output: {
      verdict: "wrong",
      target_ok: false,
      error_tags: ["be.missing"],
      error_spans: [{ text: "very", tag: "be.missing" }],
      ladder: {
        h1: "Cümlede bir kelime eksik.",
        h2: "'I' ile 'very' arasına bak.",
        h3:
          "Cümlede fiil yoksa be gerekir: I ile am, he/she/it ile is, you/we/they ile are.",
        h4: "I am very happy.",
      },
      variant_to_learn: "",
      confidence: 0.95,
    },
  },
  {
    item: {
      key: "en.ws.tell.v.1",
      prompt_l1: "Bana doğruyu söyle.",
      reference_l2: "Tell me the truth.",
      target_span: "Tell",
      grammar_codes: ["gp.imperative"],
    },
    response: {
      text: "say me the truth",
      source: "asr",
      asr_confidence: 0.91,
    },
    output: {
      verdict: "wrong",
      target_ok: false,
      error_tags: ["lex.say_tell"],
      error_spans: [{ text: "say", tag: "lex.say_tell" }],
      ladder: {
        h1: "Fiil bu cümleye uymuyor.",
        h2: "'say' kelimesine bak.",
        h3:
          "Hemen ardından kişi gelen 'söylemek' fiili say değildir; say kişiyle doğrudan kullanılmaz.",
        h4: "Tell me the truth.",
      },
      variant_to_learn: "",
      confidence: 0.9,
    },
  },
  {
    item: {
      key: "en.ws.lunch.n.1",
      prompt_l1: "Öğle yemeği planlarınız var mı?",
      reference_l2: "Do you have lunch plans?",
      target_span: "lunch",
      grammar_codes: ["gp.present_simple.questions", "gp.nouns.plural"],
    },
    response: { text: "i am hungry", source: "asr", asr_confidence: 0.97 },
    output: {
      verdict: "off_target",
      target_ok: false,
      error_tags: [],
      error_spans: [],
      ladder: {
        h1: "İstenen anlam bu değil.",
        h2: "Cümle, öğle yemeği için bir planın olup olmadığını soruyor.",
        h3:
          "Evet/hayır sorusu yardımcı fiille başlar, sonra özne ve fiil gelir.",
        h4: "Do you have lunch plans?",
      },
      variant_to_learn: "",
      confidence: 0.95,
    },
  },
  {
    item: {
      key: "en.ws.plan.n.1",
      prompt_l1: "Öğle yemeği planlarınız var mı?",
      reference_l2: "Do you have lunch plans?",
      target_span: "plans",
      grammar_codes: ["gp.present_simple.questions", "gp.nouns.plural"],
    },
    response: {
      text: "the fun uh lunge plan snow",
      source: "asr",
      asr_confidence: 0.42,
    },
    output: {
      verdict: "unintelligible",
      target_ok: false,
      error_tags: [],
      error_spans: [],
      ladder: none,
      variant_to_learn: "",
      confidence: 0.8,
    },
  },
  {
    item: {
      key: "en.gp.can.ability",
      prompt_l1: "Yüzebilirim.",
      reference_l2: "I can swim.",
      target_span: "I can swim",
      grammar_codes: ["gp.can.ability"],
    },
    response: { text: "i can't swim", source: "asr", asr_confidence: 0.62 },
    output: {
      verdict: "uncertain",
      target_ok: false,
      error_tags: [],
      error_spans: [],
      ladder: none,
      variant_to_learn: "",
      confidence: 0.4,
    },
  },
];

/** The call's input as the model sees it: fixed key order, no extras. */
export function answerCheckUserMessage(input: AnswerCheckInput): string {
  const { ctx, item, response } = input;
  return JSON.stringify({
    ctx: {
      l1: ctx.l1,
      l2: ctx.l2,
      level: ctx.level,
      explain_in: ctx.explain_in,
    },
    item: {
      key: item.key,
      prompt_l1: item.prompt_l1,
      reference_l2: item.reference_l2,
      variants: item.variants,
      alternatives: item.alternatives,
      target_span: item.target_span,
      grammar_codes: item.grammar_codes,
      ...(item.context_note ? { context_note: item.context_note } : {}),
    },
    response: {
      text: response.text,
      source: response.source,
      ...(response.asr_confidence === undefined
        ? {}
        : { asr_confidence: response.asr_confidence }),
    },
    attempt_no: input.attempt_no,
    previous_responses: input.previous_responses,
  });
}

function exampleText(example: Example): string {
  const input = answerCheckUserMessage({
    ctx: {
      l1: "tr",
      l2: "en",
      level: (example.level ?? "A1") as AnswerCheckInput["ctx"]["level"],
      explain_in: "l1",
    },
    item: {
      prompt_l1: "",
      reference_l2: "",
      variants: [],
      alternatives: [],
      target_span: "",
      grammar_codes: [],
      ...example.item,
    },
    response: example.response,
    attempt_no: 1,
    previous_responses: [],
  });
  return `Input: ${input}\nOutput: ${JSON.stringify(example.output)}`;
}

/** The fixed system prompt for [catalog]. */
export function answerCheckSystemPrompt(catalog: Catalog): string {
  const tags = catalog.errorTags
    .filter((tag) => answerCheckCategories.includes(tag.category))
    .map((tag) => `- ${tag.code}: ${tag.description} (${tag.example})`)
    .join("\n");
  return [
    rules,
    `# Error tags (${catalog.pack})\n${tags}`,
    `# Examples\n${examples.map(exampleText).join("\n\n")}`,
    "Answer with one JSON object that matches the schema, nothing else.",
  ].join("\n\n");
}

/** Keys of the example items; eval cases must not reuse their sentences. */
export const exampleSentences = examples.map((e) => e.item.reference_l2);
