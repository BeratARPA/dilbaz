/**
 * `tutor/answer_check` (docs/07-ai-tutor.md §4.1): judges a card answer that
 * the deterministic check could not match (docs/03 §0.5) and returns the
 * whole hint ladder in one call.
 *
 * The model's answer is checked with zod against the pair's closed tag
 * list; then the server applies what a prompt cannot promise: no ladder
 * for answers that need none, no hint that gives the answer away (blank
 * hints are filled by the client's templates), spans only where the quoted
 * words are.
 */
import type { Catalog } from "../_shared/catalogs/catalog.ts";
import { catalogs } from "../_shared/catalogs/index.ts";
import { leaks } from "../_shared/leak.ts";
import { providerSchema } from "../_shared/llm/json_schema.ts";
import type { JsonSchema } from "../_shared/llm/types.ts";
import { answerCheckSystemPrompt } from "../_shared/prompts/answer_check.ts";
import {
  answerCheckCategories,
  type AnswerCheckInput,
  type AnswerCheckOutput,
  type AnswerCheckWire,
  answerCheckWire,
  errorVerdicts,
} from "../_shared/schemas/answer_check.ts";

/** What answer_check needs for one language pair, built once. */
export interface AnswerCheckKit {
  catalog: Catalog;
  system: string;
  schema: JsonSchema;
  wire: ReturnType<typeof answerCheckWire>;
}

const kits = new Map<string, AnswerCheckKit>();

/** The kit of `<l1>-<l2>`, or null for a pair without a catalog. */
export function kitFor(pair: string): AnswerCheckKit | null {
  const cached = kits.get(pair);
  if (cached) return cached;
  const catalog = catalogs[pair];
  if (!catalog) return null;
  const tags = catalog.errorTags
    .filter((tag) => answerCheckCategories.includes(tag.category))
    .map((tag) => tag.code);
  const wire = answerCheckWire(tags as [string, ...string[]]);
  const kit = {
    catalog,
    system: answerCheckSystemPrompt(catalog),
    schema: providerSchema(wire),
    wire,
  };
  kits.set(pair, kit);
  return kit;
}

/** The model's text as an answer, or null when it is not a valid one. */
export function parseWire(
  kit: AnswerCheckKit,
  text: string,
): AnswerCheckWire | null {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    return null;
  }
  const parsed = kit.wire.safeParse(json);
  if (!parsed.success) return null;
  // A ladder without the corrected sentence cannot end the card.
  if (
    errorVerdicts.includes(parsed.data.verdict) &&
    parsed.data.ladder.h4.trim() === ""
  ) {
    return null;
  }
  return parsed.data;
}

const maxTags = 3;
const maxSpans = 5;
const hints = ["h1", "h2", "h3"] as const;

/** Character ranges of the quoted words, left to right; unfound ones drop. */
function spansOf(
  response: string,
  quoted: AnswerCheckWire["error_spans"],
  tags: readonly string[],
): AnswerCheckOutput["error_spans"] {
  const lower = response.toLowerCase();
  const taken: [number, number][] = [];
  const spans: AnswerCheckOutput["error_spans"] = [];
  for (const { text, tag } of quoted) {
    const needle = text.trim().toLowerCase();
    if (needle === "" || !tags.includes(tag)) continue;
    let from = 0;
    for (;;) {
      const start = lower.indexOf(needle, from);
      if (start < 0) break;
      const end = start + needle.length;
      if (!taken.some(([s, e]) => start < e && s < end)) {
        taken.push([start, end]);
        spans.push({ start, end, tag });
        break;
      }
      from = start + 1;
    }
    if (spans.length === maxSpans) break;
  }
  return spans.sort((a, b) => a.start - b.start);
}

export interface Guarded {
  output: AnswerCheckOutput;
  /** Hints blanked by the leak check. */
  leaked: string[];
}

/** The route's answer from a valid model answer (docs/07 §4.1, §6). */
export function guard(
  input: AnswerCheckInput,
  wire: AnswerCheckWire,
  kit: AnswerCheckKit,
  served: { provider: string; model: string },
): Guarded {
  const response = input.response.text;
  // Only speech can be unintelligible; unreadable typing misses the meaning.
  const verdict = wire.verdict === "unintelligible" &&
      input.response.source === "typed"
    ? "off_target"
    : wire.verdict;
  const targetOk = verdict === "correct"
    ? true
    : verdict === "wrong" || verdict === "off_target" ||
        verdict === "unintelligible"
    ? false
    : wire.target_ok;
  const tagged = verdict === "minor_error" || verdict === "wrong";
  const tags = tagged ? [...new Set(wire.error_tags)].slice(0, maxTags) : [];

  const ladder = errorVerdicts.includes(verdict)
    ? { ...wire.ladder }
    : { h1: "", h2: "", h3: "", h4: "" };
  const leaked: string[] = [];
  const context = {
    response,
    correction: ladder.h4,
    reference: input.item.reference_l2,
    targetSpan: input.item.target_span,
    ruleNotes: input.item.grammar_codes
      .map((code) => kit.catalog.ruleNotes[code])
      .filter((note): note is string => note !== undefined),
  };
  for (const hint of hints) {
    if (ladder[hint] !== "" && leaks(ladder[hint], context)) {
      ladder[hint] = "";
      leaked.push(hint);
    }
  }

  return {
    output: {
      verdict,
      target_ok: targetOk,
      error_tags: tags,
      error_spans: spansOf(response, wire.error_spans, tags),
      ladder,
      variant_to_learn: verdict === "acceptable_variant"
        ? response.trim()
        : null,
      confidence: wire.confidence,
      catalog: kit.catalog.pack,
      provider: served.provider,
      model: served.model,
    },
    leaked,
  };
}
