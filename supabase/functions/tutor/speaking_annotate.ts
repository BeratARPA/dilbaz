/**
 * `tutor/speaking_annotate` (docs/07-ai-tutor.md §4.2): marks a speaking
 * task's transcript (A11, A23).
 *
 * The model's answer is checked with zod against the pair's closed tags and
 * the pack's grammar codes; then the server keeps what a prompt cannot
 * promise: marks inside the transcript, clauses in order without overlap,
 * `error_free` as the marked errors say, at most two strengths, at most
 * five corrections, and no hint that gives a correction away (blank hints
 * are filled by the client's templates). No number is computed here.
 */
import type { Catalog } from "../_shared/catalogs/catalog.ts";
import { catalogs } from "../_shared/catalogs/index.ts";
import { leaks } from "../_shared/leak.ts";
import { providerSchema } from "../_shared/llm/json_schema.ts";
import type { JsonSchema } from "../_shared/llm/types.ts";
import {
  speakingAnnotatePromptVersion,
  speakingAnnotateSystemPrompt,
  speakingCategories,
} from "../_shared/prompts/speaking_annotate.ts";
import {
  type SpeakingAnnotateInput,
  type SpeakingAnnotateOutput,
  type SpeakingAnnotateWire,
  speakingAnnotateWire,
} from "../_shared/schemas/speaking_annotate.ts";

/** What speaking_annotate needs for one language pair, built once. */
export interface SpeakingAnnotateKit {
  catalog: Catalog;
  system: string;
  schema: JsonSchema;
  wire: ReturnType<typeof speakingAnnotateWire>;
}

const kits = new Map<string, SpeakingAnnotateKit>();

/** The kit of `<l1>-<l2>`, or null for a pair without a catalog. */
export function annotateKitFor(pair: string): SpeakingAnnotateKit | null {
  const cached = kits.get(pair);
  if (cached) return cached;
  const catalog = catalogs[pair];
  if (!catalog) return null;
  const tags = catalog.errorTags
    .filter((tag) => speakingCategories.includes(tag.category))
    .map((tag) => tag.code);
  const codes = Object.keys(catalog.ruleNotes);
  const wire = speakingAnnotateWire(
    tags as [string, ...string[]],
    codes as [string, ...string[]],
  );
  const kit = {
    catalog,
    system: speakingAnnotateSystemPrompt(catalog),
    schema: providerSchema(wire),
    wire,
  };
  kits.set(pair, kit);
  return kit;
}

/** The model's text as an answer, or null when it is not a valid one. */
export function parseAnnotateWire(
  kit: SpeakingAnnotateKit,
  text: string,
): SpeakingAnnotateWire | null {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    return null;
  }
  const parsed = kit.wire.safeParse(json);
  return parsed.success ? parsed.data : null;
}

export const maxStrengths = 2;
export const maxCorrections = 5;
const maxErrors = 80;
const maxText = 300;
const hints = ["h1", "h2", "h3"] as const;

export interface Annotated {
  output: SpeakingAnnotateOutput;
  /** Hints blanked by the leak check, as `<correction>.<hint>`. */
  leaked: string[];
}

/** The route's answer from a valid model answer (docs/07 §4.2, §6). */
export function annotationOutput(
  input: SpeakingAnnotateInput,
  wire: SpeakingAnnotateWire,
  kit: SpeakingAnnotateKit,
  served: { provider: string; model: string },
): Annotated {
  const last = input.words.length - 1;
  const inside = (span: { start_i: number; end_i: number }) =>
    span.start_i <= span.end_i && span.end_i <= last;

  const errors = wire.errors.filter(inside).slice(0, maxErrors);
  const clauses: SpeakingAnnotateWire["clauses"] = [];
  for (
    const clause of wire.clauses.filter(inside)
      .sort((a, b) => a.start_i - b.start_i)
  ) {
    const before = clauses.at(-1);
    if (before && clause.start_i <= before.end_i) continue;
    clauses.push({
      ...clause,
      // A clause is error-free when no marked error starts in it.
      error_free: !errors.some((error) =>
        clause.start_i <= error.start_i && error.start_i <= clause.end_i
      ),
    });
  }
  const fillerAt = new Set<number>();
  const fillers = wire.fillers.filter((filler) => {
    if (filler.i > last || fillerAt.has(filler.i)) return false;
    fillerAt.add(filler.i);
    return true;
  });

  const leaked: string[] = [];
  const corrections = wire.corrections
    .filter((c) =>
      c.original.trim() !== "" && c.corrected.trim() !== "" &&
      c.original.length <= maxText && c.corrected.length <= maxText &&
      c.original.trim() !== c.corrected.trim()
    )
    .slice(0, maxCorrections)
    .map((correction, index) => {
      const ladder = { ...correction.ladder };
      for (const hint of hints) {
        if (
          leaks(ladder[hint], {
            response: correction.original,
            correction: correction.corrected,
            reference: correction.corrected,
            targetSpan: "",
            ruleNotes: [],
          })
        ) {
          ladder[hint] = "";
          leaked.push(`${index}.${hint}`);
        }
      }
      return { ...correction, ladder };
    });

  return {
    output: {
      clauses,
      errors,
      fillers,
      repairs: wire.repairs.filter(inside),
      structures_used: wire.structures_used.filter(inside),
      task_outcome: wire.task_outcome,
      strengths: wire.strengths
        .map((strength) => strength.trim())
        .filter((strength) => strength !== "" && strength.length <= maxText)
        .slice(0, maxStrengths),
      corrections,
      catalog: kit.catalog.pack,
      prompt_version: speakingAnnotatePromptVersion,
      provider: served.provider,
      model: served.model,
    },
    leaked,
  };
}
