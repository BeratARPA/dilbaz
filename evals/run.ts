/**
 * Runs an LLM route's gold set against its candidate models
 * (docs/07-ai-tutor.md §8).
 *
 *   cd evals
 *   deno run -A --env-file=../supabase/functions/.env run.ts \
 *     --route answer_check|gap_suggest|speaking_annotate [--models <id>,<id>]
 *     [--limit <n>]
 *     [--ids <id>,<id>]
 *
 * Each case goes the way the app's request goes in the tutor function: the
 * same prompt, schema, retries and guards. It uses the free quotas, so tell
 * the user how long it takes and what it uses before running it
 * (CLAUDE.md).
 *
 * Results: `results/<route>.<model>.jsonl` keeps one line per case and
 * prompt version, so a run cut short by a daily quota goes on where it
 * stopped; `results/<date>-<route>.json` holds the scores.
 */
import { dirname, fromFileUrl, join } from "@std/path";
import { leaks } from "../supabase/functions/_shared/leak.ts";
import { aboveLevel } from "../supabase/functions/_shared/levels/levels.ts";
import { geminiModel } from "../supabase/functions/_shared/llm/gemini.ts";
import { groqModel } from "../supabase/functions/_shared/llm/groq.ts";
import {
  type CallRecord,
  type ChainResult,
  Cooldown,
  runChain,
} from "../supabase/functions/_shared/llm/router.ts";
import type {
  LlmModel,
  LlmRequest,
} from "../supabase/functions/_shared/llm/types.ts";
import {
  llmConfig,
  type ProviderId,
  type TutorRoute,
} from "../supabase/functions/_shared/llm_config.ts";
import {
  answerCheckPromptVersion,
  answerCheckUserMessage,
} from "../supabase/functions/_shared/prompts/answer_check.ts";
import { gapSuggestPromptVersion } from "../supabase/functions/_shared/prompts/gap_suggest.ts";
import {
  speakingAnnotatePromptVersion,
  speakingAnnotateUserMessage,
} from "../supabase/functions/_shared/prompts/speaking_annotate.ts";
import { AnswerCheckInput } from "../supabase/functions/_shared/schemas/answer_check.ts";
import { GapSuggestInput } from "../supabase/functions/_shared/schemas/gap_suggest.ts";
import { SpeakingAnnotateInput } from "../supabase/functions/_shared/schemas/speaking_annotate.ts";
import {
  guard,
  kitFor,
  parseWire,
} from "../supabase/functions/tutor/answer_check.ts";
import {
  gapKitFor,
  parseGapWire,
  suggestGap,
} from "../supabase/functions/tutor/gap_suggest.ts";
import {
  annotateKitFor,
  annotationOutput,
  parseAnnotateWire,
} from "../supabase/functions/tutor/speaking_annotate.ts";
import {
  type CallResult,
  type CaseResult,
  type Expected,
  score,
} from "./score.ts";
import { type GapCaseResult, scoreGap } from "./score_gap.ts";
import { scoreSpeaking, type SpeakingCaseResult } from "./score_speaking.ts";
import type { SpeakingExpected } from "./speaking_cases.ts";

const here = dirname(fromFileUrl(import.meta.url));

/** Least time between two calls to one provider (its per-minute limit). */
const pace: Record<ProviderId, number> = { gemini: 6_000, groq: 2_500 };
/** Wait after a per-minute 429 before the case is tried again. */
const busyWaitMs = 30_000;
const busyTries = 5;

const routes = ["answer_check", "gap_suggest", "speaking_annotate"] as const;
type EvalRoute = typeof routes[number];

interface GoldCase {
  id: string;
  input: unknown;
  /** The route's own gold: `Expected` or `SpeakingExpected`. */
  expected?: unknown;
}

interface Args {
  route: EvalRoute;
  models: string[];
  limit?: number;
  ids?: Set<string>;
}

function parseArgs(argv: string[]): Args | null {
  const value = (name: string) => {
    const at = argv.indexOf(`--${name}`);
    return at >= 0 ? argv[at + 1] : undefined;
  };
  const list = (name: string) =>
    value(name)?.split(",").map((s) => s.trim()).filter((s) => s !== "");
  const route = value("route");
  if (!routes.includes(route as EvalRoute)) return null;
  const limit = value("limit");
  return {
    route: route as EvalRoute,
    models: list("models") ??
      [...llmConfig.routes[route as TutorRoute].chain],
    limit: limit ? Number(limit) : undefined,
    ids: list("ids") ? new Set(list("ids")) : undefined,
  };
}

function modelOf(id: string): LlmModel {
  const config = llmConfig.models[id];
  if (!config) throw new Error(`${id} is not in llm_config.ts`);
  const key = Deno.env.get(llmConfig.providers[config.provider].keyEnv);
  if (!key) {
    throw new Error(
      `${llmConfig.providers[config.provider].keyEnv} is not set (--env-file)`,
    );
  }
  return config.provider === "gemini"
    ? geminiModel(id, key)
    : groqModel(id, key);
}

const slug = (id: string) => id.replace(/[^a-z0-9.-]+/gi, "_");
const sleep = (ms: number) => new Promise((done) => setTimeout(done, ms));

async function readResults<R extends { id: string; prompt: string }>(
  path: string,
  prompt: string,
): Promise<Map<string, R>> {
  const found = new Map<string, R>();
  try {
    for (const line of (await Deno.readTextFile(path)).split("\n")) {
      if (line.trim() === "") continue;
      const result = JSON.parse(line) as R;
      if (result.prompt === prompt) found.set(result.id, result);
    }
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  return found;
}

const callResults = (calls: CallRecord[]): CallResult[] =>
  calls.map((call) => ({
    stopReason: call.stopReason,
    latencyMs: call.latencyMs,
    inputTokens: call.inputTokens,
    outputTokens: call.outputTokens,
    cachedTokens: call.cachedTokens,
  }));

/**
 * [run] once, again after a per-minute limit; "quota" when the model's day
 * is spent.
 */
async function withRetries<R extends { ok: boolean; calls: CallRecord[] }>(
  run: () => Promise<R>,
): Promise<R | "quota"> {
  for (let tries = 1;; tries++) {
    const result = await run();
    const last = result.calls.at(-1)?.stopReason;
    if (!result.ok && last === "quota") return "quota";
    if (!result.ok && last === "busy" && tries < busyTries) {
      await sleep(busyWaitMs);
      continue;
    }
    return result;
  }
}

/** The chain of the tutor function with [model] alone, for an eval. */
function chainOf<T>(
  model: LlmModel,
  request: Omit<LlmRequest, "effort" | "maxTokens" | "timeoutMs">,
  route: TutorRoute,
  accept: (text: string) => T | null,
): Promise<ChainResult<T>> {
  const config = llmConfig.routes[route];
  return runChain(
    {
      models: [model],
      consent: true,
      use: new Map(),
      cooldown: new Cooldown(),
      now: () => performance.now(),
    },
    {
      ...request,
      effort: config.effort,
      maxTokens: config.maxTokens,
      timeoutMs: config.timeoutMs,
    },
    accept,
  );
}

/** One answer_check case through the tutor's chain with [model] alone. */
async function runAnswerCheck(
  model: LlmModel,
  gold: GoldCase,
  paced: () => Promise<void>,
): Promise<CaseResult | "quota"> {
  const input = AnswerCheckInput.parse(gold.input);
  const kit = kitFor(`${input.ctx.l1}-${input.ctx.l2}`);
  if (!kit) throw new Error(`${gold.id}: no catalog`);
  const base: CaseResult = {
    id: gold.id,
    model: model.id,
    prompt: answerCheckPromptVersion,
    level: input.ctx.level,
    expected: gold.expected as Expected,
    calls: [],
  };
  const result = await withRetries(async () => {
    await paced();
    return chainOf(
      model,
      {
        system: kit.system,
        user: answerCheckUserMessage(input),
        schemaName: "answer_check",
        schema: kit.schema,
      },
      "answer_check",
      (text) => parseWire(kit, text),
    );
  });
  if (result === "quota") return result;
  const calls = callResults(result.calls);
  if (!result.ok) return { ...base, code: result.code, calls };
  const { output, leaked } = guard(input, result.value, kit, {
    provider: model.provider,
    model: model.id,
  });
  const context = {
    response: input.response.text,
    correction: output.ladder.h4,
    reference: input.item.reference_l2,
    targetSpan: input.item.target_span,
    ruleNotes: input.item.grammar_codes
      .map((code) => kit.catalog.ruleNotes[code])
      .filter((note): note is string => note !== undefined),
  };
  return {
    ...base,
    verdict: output.verdict,
    target_ok: output.target_ok,
    error_tags: output.error_tags,
    ladder: output.ladder,
    leaked,
    servedLeaks: (["h1", "h2", "h3"] as const)
      .filter((h) =>
        output.ladder[h] !== "" && leaks(output.ladder[h], context)
      )
      .length,
    calls,
  };
}

/** One gap_suggest case: the first call and, if needed, the simplify one. */
async function runGapSuggest(
  model: LlmModel,
  gold: GoldCase,
  paced: () => Promise<void>,
): Promise<GapCaseResult | "quota"> {
  const input = GapSuggestInput.parse(gold.input);
  const kit = gapKitFor(input.ctx.l2);
  if (!kit) throw new Error(`${gold.id}: no word levels for ${input.ctx.l2}`);
  const base: GapCaseResult = {
    id: gold.id,
    model: model.id,
    prompt: gapSuggestPromptVersion,
    level: input.ctx.level,
    calls: [],
  };
  const result = await withRetries(() =>
    suggestGap(input, kit, async (user) => {
      // Each call, the simplify one too, keeps the provider's pace.
      await paced();
      return chainOf(
        model,
        {
          system: kit.system,
          user,
          schemaName: "gap_suggest",
          schema: kit.schema,
        },
        "gap_suggest",
        parseGapWire,
      );
    })
  );
  if (result === "quota") return result;
  const calls = callResults(result.calls);
  if (!result.ok) return { ...base, code: result.code, calls };
  const output = result.output;
  return {
    ...base,
    l2_natural: output.l2_natural,
    l2_simple: output.l2_simple,
    key_chunk: output.key_chunk,
    notes_l1: output.notes_l1,
    above: aboveLevel(output.l2_simple, input.ctx.level, kit.lexicon),
    simplified: output.simplified,
    calls,
  };
}

/** One speaking_annotate case through the tutor's chain with [model] alone. */
async function runSpeakingAnnotate(
  model: LlmModel,
  gold: GoldCase,
  paced: () => Promise<void>,
): Promise<SpeakingCaseResult | "quota"> {
  const input = SpeakingAnnotateInput.parse(gold.input);
  const kit = annotateKitFor(`${input.ctx.l1}-${input.ctx.l2}`);
  if (!kit) throw new Error(`${gold.id}: no catalog`);
  const base: SpeakingCaseResult = {
    id: gold.id,
    model: model.id,
    prompt: speakingAnnotatePromptVersion,
    level: input.ctx.level,
    expected: gold.expected as SpeakingExpected,
    calls: [],
  };
  const result = await withRetries(async () => {
    await paced();
    return chainOf(
      model,
      {
        system: kit.system,
        user: speakingAnnotateUserMessage(input),
        schemaName: "speaking_annotate",
        schema: kit.schema,
      },
      "speaking_annotate",
      (text) => parseAnnotateWire(kit, text),
    );
  });
  if (result === "quota") return result;
  const calls = callResults(result.calls);
  if (!result.ok) return { ...base, code: result.code, calls };
  const { output, leaked } = annotationOutput(input, result.value, kit, {
    provider: model.provider,
    model: model.id,
  });
  const clauses = output.clauses;
  return {
    ...base,
    errors: output.errors.map(({ start_i, end_i, tag }) => ({
      start_i,
      end_i,
      tag,
    })),
    clauses: clauses.length,
    efc: clauses.length === 0
      ? null
      : clauses.filter((c) => c.error_free).length / clauses.length,
    outcome: output.task_outcome,
    leaked,
    calls,
  };
}

const promptOf: Record<EvalRoute, string> = {
  answer_check: answerCheckPromptVersion,
  gap_suggest: gapSuggestPromptVersion,
  speaking_annotate: speakingAnnotatePromptVersion,
};

async function main() {
  const args = parseArgs(Deno.args);
  if (!args) {
    console.error(
      "usage: run.ts --route answer_check|gap_suggest|speaking_annotate " +
        "[--models a,b] " +
        "[--limit n] [--ids x,y]",
    );
    Deno.exit(2);
  }
  const route = args.route;
  const prompt = promptOf[route];
  const lines = await Deno.readTextFile(
    join(here, "tutor", route, "cases.jsonl"),
  );
  const gold = lines.split("\n").filter((l) => l.trim() !== "")
    .map((l) => JSON.parse(l) as GoldCase)
    .filter((c) => !args.ids || args.ids.has(c.id))
    .slice(0, args.limit);
  const models = args.models.map(modelOf);
  await Deno.mkdir(join(here, "results"), { recursive: true });

  const scores = [];
  for (const model of models) {
    const path = join(here, "results", `${route}.${slug(model.id)}.jsonl`);
    const results = await readResults<
      CaseResult | GapCaseResult | SpeakingCaseResult
    >(path, prompt);
    const todo = gold.filter((c) => !results.has(c.id));
    console.log(`${model.id}: ${results.size} done, ${todo.length} to run`);
    let last = 0;
    const paced = async () => {
      const wait = last + pace[model.provider] - Date.now();
      if (wait > 0) await sleep(wait);
      last = Date.now();
    };
    for (const [index, goldCase] of todo.entries()) {
      const result = route === "answer_check"
        ? await runAnswerCheck(model, goldCase, paced)
        : route === "gap_suggest"
        ? await runGapSuggest(model, goldCase, paced)
        : await runSpeakingAnnotate(model, goldCase, paced);
      if (result === "quota") {
        console.log(
          `${model.id}: daily quota reached; run again after it resets`,
        );
        break;
      }
      results.set(result.id, result);
      await Deno.writeTextFile(path, JSON.stringify(result) + "\n", {
        append: true,
      });
      if ((index + 1) % 10 === 0) {
        console.log(`${model.id}: ${index + 1}/${todo.length}`);
      }
    }
    const scored = gold.map((c) => results.get(c.id))
      .filter((r) => r !== undefined);
    const complete = scored.length === gold.length;
    scores.push(
      route === "answer_check"
        ? { ...score(model.id, scored as CaseResult[]), complete }
        : route === "gap_suggest"
        ? { ...scoreGap(model.id, scored as GapCaseResult[]), complete }
        : {
          ...scoreSpeaking(model.id, scored as SpeakingCaseResult[]),
          complete,
        },
    );
  }

  const date = new Date().toISOString().slice(0, 10);
  const summary = { route, prompt, date, cases: gold.length, scores };
  await Deno.writeTextFile(
    join(here, "results", `${date}-${route}.json`),
    JSON.stringify(summary, null, 2) + "\n",
  );
  for (const s of scores) console.log(JSON.stringify(s));
}

if (import.meta.main) await main();
