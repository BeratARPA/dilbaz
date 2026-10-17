/**
 * `tutor/pron_check` (docs/07-ai-tutor.md §4.4, ADR-0011): hears a
 * shadowed sentence (A07).
 *
 * The model's answer is checked with zod against the pair's pronunciation
 * tags; then the server keeps what a prompt cannot promise: indices inside
 * the sentence, one problem per word and tag, nothing when uncertain, and
 * the word as the server numbered it. Nothing is scored here.
 */
import type { Catalog } from "../_shared/catalogs/catalog.ts";
import { catalogs } from "../_shared/catalogs/index.ts";
import { providerSchema } from "../_shared/llm/json_schema.ts";
import type { JsonSchema } from "../_shared/llm/types.ts";
import {
  pronCategory,
  pronCheckPromptVersion,
  pronCheckSystemPrompt,
  referenceWords,
} from "../_shared/prompts/pron_check.ts";
import {
  type PronCheckInput,
  type PronCheckOutput,
  type PronCheckWire,
  pronCheckWire,
} from "../_shared/schemas/pron_check.ts";

/** What pron_check needs for one language pair, built once. */
export interface PronCheckKit {
  catalog: Catalog;
  system: string;
  schema: JsonSchema;
  wire: ReturnType<typeof pronCheckWire>;
}

const kits = new Map<string, PronCheckKit>();

/** The kit of `<l1>-<l2>`, or null for a pair without pronunciation tags. */
export function pronKitFor(pair: string): PronCheckKit | null {
  const cached = kits.get(pair);
  if (cached) return cached;
  const catalog = catalogs[pair];
  if (!catalog) return null;
  const tags = catalog.errorTags
    .filter((tag) => tag.category === pronCategory)
    .map((tag) => tag.code);
  if (tags.length === 0) return null;
  const wire = pronCheckWire(tags as [string, ...string[]]);
  const kit = {
    catalog,
    system: pronCheckSystemPrompt(catalog),
    schema: providerSchema(wire),
    wire,
  };
  kits.set(pair, kit);
  return kit;
}

/** The model's text as an answer, or null when it is not a valid one. */
export function parsePronWire(
  kit: PronCheckKit,
  text: string,
): PronCheckWire | null {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    return null;
  }
  const parsed = kit.wire.safeParse(json);
  return parsed.success ? parsed.data : null;
}

export const maxIssues = 6;
const maxHeard = 40;

/** The route's answer from a valid model answer. */
export function pronOutput(
  input: PronCheckInput,
  wire: PronCheckWire,
  kit: PronCheckKit,
  served: { provider: string; model: string },
): PronCheckOutput {
  const words = referenceWords(input.reference);
  const seen = new Set<string>();
  const issues = wire.uncertain ? [] : wire.issues
    .filter((issue) => {
      const key = `${issue.i}:${issue.tag}`;
      if (issue.i >= words.length || seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, maxIssues)
    .map((issue) => ({
      i: issue.i,
      word: words[issue.i],
      tag: issue.tag,
      heard: issue.heard.trim().slice(0, maxHeard),
    }));
  return {
    uncertain: wire.uncertain,
    issues,
    catalog: kit.catalog.pack,
    prompt_version: pronCheckPromptVersion,
    provider: served.provider,
    model: served.model,
  };
}
