/**
 * `pron_check` prompt (docs/07-ai-tutor.md §4.4, §5; ADR-0011).
 *
 * The system prompt is fixed: role, rules and the pair's pronunciation
 * tags, so that providers can cache it. The user message carries the
 * numbered sentence; the recording goes with it. Changing this file means
 * a new version and an eval run (docs/07 §8).
 */
import type { Catalog } from "../catalogs/catalog.ts";
import type { PronCheckInput } from "../schemas/pron_check.ts";

export const pronCheckPromptVersion = "pron_check@2";

/** The catalog category this route judges. */
export const pronCategory = "pronunciation";

const rules =
  `You listen for Dilbaz, a language app. A learner heard an English sentence and repeated it. You get the recording and the sentence, its words numbered. You report how each word actually sounded, and which words were pronounced in a way that would make them hard to understand. The app shows the learner at most two problems; it never shows a score.

# How to listen
- Judge the sound you hear, not what learners often get wrong. Do not expect mistakes: most words of most recordings are said well, and the most common right answer is an empty issues list.
- First write words: for every numbered word, in order, i and sounded = how it actually sounded in this recording, in IPA. Write what you hear, even when it is the standard pronunciation.
- Then compare each sounded with the word's standard pronunciations (American, British and other standard accents are all right). A word has a problem only when its sound clearly differs from all of them in a way of the tag catalog below.

# What to mark
- issues: one per problem, on the word where you hear it: i = the word's number, tag = the problem's tag, heard = how the word sounded, in plain letters a Turkish speaker can read.
- The criterion is being understood, not a native accent. A foreign accent that does not change or blur the word is all right.
- When you are not sure a word was said wrong, do not mark it. A wrong alarm teaches the learner a mistake they did not make.
- Do not mark words left out, added or replaced with another word: the app finds those from speech recognition. Do not mark hesitations, repeats or speed.
- A word may have two problems of different tags; never the same tag twice on one word.
- uncertain: true when the recording is silent, mostly noise, cut off, or clearly not this sentence; then issues is empty.

# Rules
- Use only tags of the tag catalog; never invent one.
- Indices must be numbers of the given words.`;

/** The fixed system prompt of a pair: rules and its pronunciation tags. */
export function pronCheckSystemPrompt(catalog: Catalog): string {
  const tags = catalog.errorTags
    .filter((tag) => tag.category === pronCategory)
    // No examples: they made the model hear them (pron_check@1 eval).
    .map((tag) => `- ${tag.code}: ${tag.description}`)
    .join("\n");
  return `${rules}\n\n# Tag catalog (${catalog.pack})\nDescriptions are in the learner's language.\n${tags}`;
}

/** The words of [reference] the way the route numbers them. */
export function referenceWords(reference: string): string[] {
  return reference
    .split(/\s+/)
    .map((word) => word.replace(/^[^\p{L}\p{N}']+|[^\p{L}\p{N}']+$/gu, ""))
    .filter((word) => word !== "");
}

/** The call's own message: the learner's level and the numbered sentence. */
export function pronCheckUserMessage(input: PronCheckInput): string {
  const words = referenceWords(input.reference)
    .map((word, i) => `[${i}]${word}`)
    .join(" ");
  return [
    `Learner level: ${input.ctx.level}`,
    `Sentence: ${input.reference}`,
    `Numbered words: ${words}`,
    "The recording is attached.",
  ].join("\n");
}
