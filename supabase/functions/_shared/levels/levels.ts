/**
 * Word levels of a target language (docs/07-ai-tutor.md §4.3): which
 * words of an LLM's English are above the learner's level plus one.
 *
 * The data comes from the target pack's lexicon, written by
 * `dilbaz-content levels-module`. A word is known by its lemmas; a form
 * that belongs to several lemmas ("saw": see, saw) takes the lowest level.
 * Words the lexicon does not know (names, numbers, rare words) are not
 * counted: there is nothing to tell their level by.
 */

export const levelCodes = ["A0", "A1", "A2", "B1", "B2", "C1", "C2"] as const;
export type LevelCode = typeof levelCodes[number];

/** A level's place on the scale: A0 = 0 … C2 = 6 (docs/04 §7). */
export const scaleOf = (level: LevelCode): number => levelCodes.indexOf(level);

/** The generated data of one target pack. */
export interface LevelData {
  /** The pack it was written from, such as `en@1`. */
  pack: string;
  /** Lemmas by level, separated by spaces. */
  lemmas: Partial<Record<LevelCode, string>>;
  /**
   * "form lemma[/lemma…]" pairs separated by "|": every form that is not a
   * lemma itself, or belongs to another lemma too.
   */
  forms: string;
}

/** Clitics written onto a word; the words they stand for are all A1. */
const clitics = ["n't", "'s", "'re", "'m", "'ll", "'ve", "'d"];
const negations: Record<string, string> = {
  "can't": "can",
  "won't": "will",
  "shan't": "shall",
};

export class Lexicon {
  readonly pack: string;
  readonly #levels = new Map<string, number>();
  readonly #forms = new Map<string, string[]>();

  constructor(data: LevelData) {
    this.pack = data.pack;
    for (const [code, words] of Object.entries(data.lemmas)) {
      const scale = scaleOf(code as LevelCode);
      for (const word of (words ?? "").split(" ")) {
        if (word !== "") this.#levels.set(word, scale);
      }
    }
    for (const pair of data.forms.split("|")) {
      const [form, lemmas] = pair.split(" ");
      if (form && lemmas) this.#forms.set(form, lemmas.split("/"));
    }
  }

  /** The level of [word] on the scale; null for a word it does not know. */
  levelOf(word: string): number | null {
    const key = word.toLowerCase();
    const levels = [key, ...(this.#forms.get(key) ?? [])]
      .map((lemma) => this.#levels.get(lemma))
      .filter((level): level is number => level !== undefined);
    return levels.length === 0 ? null : Math.min(...levels);
  }
}

/** The words of [text], lowercase, with clitics taken off. */
export function words(text: string): string[] {
  const found: string[] = [];
  const normalized = text.toLowerCase().replace(/[’‘]/g, "'");
  for (const match of normalized.matchAll(/[a-z]+(?:['.-][a-z]+)*/g)) {
    let word = match[0];
    const negation = negations[word];
    if (negation) {
      found.push(negation);
      continue;
    }
    for (const clitic of clitics) {
      if (word.endsWith(clitic) && word.length > clitic.length) {
        word = word.slice(0, -clitic.length);
        break;
      }
    }
    found.push(word);
  }
  return found;
}

/**
 * The words of each sentence of [text] that are above [level] + 1, in
 * order and each once (docs/07 §8: at most one per sentence).
 */
export function aboveLevel(
  text: string,
  level: LevelCode,
  lexicon: Lexicon,
): string[][] {
  const ceiling = scaleOf(level) + 1;
  return text.split(/[.!?]+(?:\s|$)/)
    .filter((sentence) => sentence.trim() !== "")
    .map((sentence) => {
      const above = words(sentence).filter((word) => {
        const found = lexicon.levelOf(word);
        return found !== null && found > ceiling;
      });
      return [...new Set(above)];
    });
}
