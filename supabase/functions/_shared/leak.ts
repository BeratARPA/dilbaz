/**
 * Hints H1–H3 must not give the answer away (I-02, docs/07-ai-tutor.md
 * §4.1, §6). The prompt says so; this check makes sure of it.
 *
 * A hint leaks when it contains, as words:
 * - the corrected sentence (H4) or the reference, or
 * - the card's target phrase, when the learner did not say it as such, or
 * - a corrected target word: a word of the target or of H4 that the
 *   learner did not say. Words of the card's own rule notes are allowed:
 *   a rule names its forms ("I ile am"), and the notes are the hints the
 *   pack itself shows. Their example forms are not ("go → went" shows the
 *   answer of a past-tense card). Single letters are left out ("a", the
 *   "s" of -s).
 *
 * The same check scores the eval (docs/07 §8).
 */

/** Lowercase words; apostrophes split too, so "went'i" gives "went". */
export function words(text: string): string[] {
  return text.normalize("NFC").toLowerCase().split(/[^\p{L}\p{N}]+/u)
    .filter((word) => word !== "");
}

function containsRun(haystack: readonly string[], needle: readonly string[]) {
  if (needle.length === 0) return false;
  outer: for (let i = 0; i + needle.length <= haystack.length; i++) {
    for (let j = 0; j < needle.length; j++) {
      if (haystack[i + j] !== needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/** The form a rule note shows after an arrow: "go → went", "bad → the worst". */
const shownForm = /→[^,.;:()]*/g;

export interface LeakContext {
  /** What the learner said or typed. */
  response: string;
  /** The corrected sentence, H4. */
  correction: string;
  reference: string;
  targetSpan: string;
  /** Rule notes of the card's grammar codes. */
  ruleNotes: readonly string[];
}

export function leaks(hint: string, context: LeakContext): boolean {
  const said = words(context.response);
  const shown = words(hint);
  if (shown.length === 0) return false;

  for (const answer of [context.correction, context.reference]) {
    const answerWords = words(answer);
    if (answerWords.length >= 2 && containsRun(shown, answerWords)) return true;
  }

  const target = words(context.targetSpan);
  if (
    target.length >= 2 && !containsRun(said, target) &&
    containsRun(shown, target)
  ) {
    return true;
  }

  const saidSet = new Set(said);
  const allowed = new Set(
    context.ruleNotes.flatMap((note) => words(note.replace(shownForm, " "))),
  );
  const shownSet = new Set(shown);
  return [...target, ...words(context.correction)].some((word) =>
    word.length >= 2 && !saidSet.has(word) && !allowed.has(word) &&
    shownSet.has(word)
  );
}
