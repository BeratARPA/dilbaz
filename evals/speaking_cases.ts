/**
 * Builds the speaking_annotate gold set from its source
 * (`tutor/speaking_annotate/cases.yaml`) and the task curation, the way
 * the app sends a speaking task (docs/07-ai-tutor.md §4.2, §8).
 *
 *   cd evals && deno run -A speaking_cases.ts          # writes cases.jsonl
 *
 * Each word gets a made-up time (the annotation never reads times); error
 * quotes become word spans; the gold EFC is error-free clauses over clauses.
 */
import { dirname, fromFileUrl, join } from "@std/path";
import { parse } from "@std/yaml";

const here = dirname(fromFileUrl(import.meta.url));
const curation = join(here, "..", "content", "curation");
export const casesDir = join(here, "tutor", "speaking_annotate");

interface SourceCase {
  id: string;
  level: string;
  task: string;
  said: string;
  errors: { words: string; tag: string; nth?: number }[];
  clauses: number;
  error_free: number;
  outcome: "done" | "partial" | "not_done";
}

/** What a run compares the route's marks with. */
export interface SpeakingExpected {
  errors: { start_i: number; end_i: number; tag: string }[];
  clauses: number;
  efc: number;
  outcome: "done" | "partial" | "not_done";
}

export interface SpeakingGoldCase {
  id: string;
  input: {
    ctx: { l1: string; l2: string; level: string; explain_in: "l1" };
    task: { prompt_l1: string; goal: string; can_do_codes: string[] };
    words: { i: number; w: string; start_ms: number; end_ms: number }[];
  };
  expected: SpeakingExpected;
}

/** The span of the [nth] run of [quote]'s words in [words], or null. */
export function spanOf(
  words: readonly string[],
  quote: string,
  nth = 1,
): [number, number] | null {
  const needle = quote.split(" ");
  let seen = 0;
  outer: for (let i = 0; i + needle.length <= words.length; i++) {
    for (let j = 0; j < needle.length; j++) {
      if (words[i + j] !== needle[j]) continue outer;
    }
    if (++seen === nth) return [i, i + needle.length - 1];
  }
  return null;
}

/** The gold cases, from the sources. */
export async function buildCases(): Promise<SpeakingGoldCase[]> {
  const sources = parse(
    await Deno.readTextFile(join(casesDir, "cases.yaml")),
  ) as SourceCase[];
  const tasks = (parse(
    await Deno.readTextFile(join(curation, "en", "tasks.yaml")),
  ) as { tasks: { id: string; goal: string; can_do: string[] }[] }).tasks;
  const instructions = (parse(
    await Deno.readTextFile(join(curation, "tr-en", "tasks.yaml")),
  ) as { instructions: { id: string; prompt: string }[] }).instructions;

  return sources.map((source) => {
    const task = tasks.find((t) => t.id === source.task);
    const instruction = instructions.find((t) => t.id === source.task);
    if (!task || !instruction) {
      throw new Error(`${source.id}: no task ${source.task}`);
    }
    const words = source.said.split(" ");
    return {
      id: source.id,
      input: {
        ctx: { l1: "tr", l2: "en", level: source.level, explain_in: "l1" },
        task: {
          prompt_l1: instruction.prompt,
          goal: task.goal,
          can_do_codes: task.can_do,
        },
        words: words.map((w, i) => ({
          i,
          w,
          start_ms: i * 500,
          end_ms: i * 500 + 350,
        })),
      },
      expected: {
        errors: source.errors.map((error) => {
          const span = spanOf(words, error.words, error.nth);
          if (!span) throw new Error(`${source.id}: "${error.words}" not said`);
          return { start_i: span[0], end_i: span[1], tag: error.tag };
        }),
        clauses: source.clauses,
        efc: source.error_free / source.clauses,
        outcome: source.outcome,
      },
    };
  });
}

/** The cases as `cases.jsonl` holds them. */
export function casesText(cases: SpeakingGoldCase[]): string {
  return cases.map((c) => JSON.stringify(c) + "\n").join("");
}

if (import.meta.main) {
  const cases = await buildCases();
  await Deno.writeTextFile(join(casesDir, "cases.jsonl"), casesText(cases));
  console.log(`${cases.length} cases`);
}
