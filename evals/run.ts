/**
 * Runs an LLM route's gold set against its candidate models
 * (docs/07-ai-tutor.md §8).
 *
 *   cd evals
 *   deno run -A --env-file=../supabase/functions/.env run.ts --route answer_check
 *     [--models <id>,<id>] [--limit <n>] [--ids <id>,<id>]
 *
 * Each case goes the way a card answer goes in the tutor function: the same
 * prompt, schema, retries and guards. It uses the free quotas, so tell the
 * user how long it takes and what it uses before running it (CLAUDE.md).
 *
 * Results: `results/answer_check.<model>.jsonl` keeps one line per case and
 * prompt version, so a run cut short by a daily quota goes on where it
 * stopped; `results/<date>-answer_check.json` holds the scores.
 */
import { dirname, fromFileUrl, join } from "@std/path";
import { leaks } from "../supabase/functions/_shared/leak.ts";
import { geminiModel } from "../supabase/functions/_shared/llm/gemini.ts";
import { groqModel } from "../supabase/functions/_shared/llm/groq.ts";
import {
  Cooldown,
  runChain,
} from "../supabase/functions/_shared/llm/router.ts";
import type { LlmModel } from "../supabase/functions/_shared/llm/types.ts";
import {
  llmConfig,
  type ProviderId,
} from "../supabase/functions/_shared/llm_config.ts";
import {
  answerCheckPromptVersion,
  answerCheckUserMessage,
} from "../supabase/functions/_shared/prompts/answer_check.ts";
import { AnswerCheckInput } from "../supabase/functions/_shared/schemas/answer_check.ts";
import {
  guard,
  kitFor,
  parseWire,
} from "../supabase/functions/tutor/answer_check.ts";
import { type CaseResult, type Expected, score } from "./score.ts";

const here = dirname(fromFileUrl(import.meta.url));

/** Least time between two calls to one provider (its per-minute limit). */
const pace: Record<ProviderId, number> = { gemini: 6_000, groq: 2_500 };
/** Wait after a per-minute 429 before the case is tried again. */
const busyWaitMs = 30_000;
const busyTries = 5;

interface GoldCase {
  id: string;
  input: unknown;
  expected: Expected;
}

interface Args {
  route: string;
  models: string[];
  limit?: number;
  ids?: Set<string>;
}

function parseArgs(argv: string[]): Args {
  const value = (name: string) => {
    const at = argv.indexOf(`--${name}`);
    return at >= 0 ? argv[at + 1] : undefined;
  };
  const list = (name: string) =>
    value(name)?.split(",").map((s) => s.trim()).filter((s) => s !== "");
  const limit = value("limit");
  return {
    route: value("route") ?? "",
    models: list("models") ?? [...llmConfig.routes.answer_check.chain],
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

async function readResults(path: string): Promise<Map<string, CaseResult>> {
  const found = new Map<string, CaseResult>();
  try {
    for (const line of (await Deno.readTextFile(path)).split("\n")) {
      if (line.trim() === "") continue;
      const result = JSON.parse(line) as CaseResult;
      if (result.prompt === answerCheckPromptVersion) {
        found.set(result.id, result);
      }
    }
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  return found;
}

/** One case through the tutor's chain with [model] alone. */
async function runCase(
  model: LlmModel,
  gold: GoldCase,
  paced: () => Promise<void>,
): Promise<CaseResult | "quota"> {
  const input = AnswerCheckInput.parse(gold.input);
  const kit = kitFor(`${input.ctx.l1}-${input.ctx.l2}`);
  if (!kit) throw new Error(`${gold.id}: no catalog`);
  const route = llmConfig.routes.answer_check;
  const base: CaseResult = {
    id: gold.id,
    model: model.id,
    prompt: answerCheckPromptVersion,
    level: input.ctx.level,
    expected: gold.expected,
    calls: [],
  };
  for (let tries = 1;; tries++) {
    await paced();
    const result = await runChain(
      {
        models: [model],
        consent: true,
        use: new Map(),
        cooldown: new Cooldown(),
        now: () => performance.now(),
      },
      {
        system: kit.system,
        user: answerCheckUserMessage(input),
        schemaName: "answer_check",
        schema: kit.schema,
        effort: route.effort,
        maxTokens: route.maxTokens,
        timeoutMs: route.timeoutMs,
      },
      (text) => parseWire(kit, text),
    );
    const calls = result.calls.map((call) => ({
      stopReason: call.stopReason,
      latencyMs: call.latencyMs,
      inputTokens: call.inputTokens,
      outputTokens: call.outputTokens,
      cachedTokens: call.cachedTokens,
    }));
    const last = calls.at(-1)?.stopReason;
    if (!result.ok && last === "quota") return "quota";
    if (!result.ok && last === "busy" && tries < busyTries) {
      await sleep(busyWaitMs);
      continue;
    }
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
}

async function main() {
  const args = parseArgs(Deno.args);
  if (args.route !== "answer_check") {
    console.error(
      "usage: run.ts --route answer_check [--models a,b] [--limit n] [--ids x,y]",
    );
    Deno.exit(2);
  }
  const lines = await Deno.readTextFile(
    join(here, "tutor", "answer_check", "cases.jsonl"),
  );
  const gold = lines.split("\n").filter((l) => l.trim() !== "")
    .map((l) => JSON.parse(l) as GoldCase)
    .filter((c) => !args.ids || args.ids.has(c.id))
    .slice(0, args.limit);
  const models = args.models.map(modelOf);
  await Deno.mkdir(join(here, "results"), { recursive: true });

  const scores = [];
  for (const model of models) {
    const path = join(here, "results", `answer_check.${slug(model.id)}.jsonl`);
    const results = await readResults(path);
    const todo = gold.filter((c) => !results.has(c.id));
    console.log(`${model.id}: ${results.size} done, ${todo.length} to run`);
    let last = 0;
    const paced = async () => {
      const wait = last + pace[model.provider] - Date.now();
      if (wait > 0) await sleep(wait);
      last = Date.now();
    };
    for (const [index, gold_case] of todo.entries()) {
      const result = await runCase(model, gold_case, paced);
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
      .filter((r): r is CaseResult => r !== undefined);
    scores.push({
      ...score(model.id, scored),
      complete: scored.length === gold.length,
    });
  }

  const date = new Date().toISOString().slice(0, 10);
  const summary = {
    route: "answer_check",
    prompt: answerCheckPromptVersion,
    date,
    cases: gold.length,
    scores,
  };
  await Deno.writeTextFile(
    join(here, "results", `${date}-answer_check.json`),
    JSON.stringify(summary, null, 2) + "\n",
  );
  for (const s of scores) {
    const pct = (x: number) => `${(x * 100).toFixed(1)}%`;
    console.log(
      `${s.model}: ${s.cases} cases${s.complete ? "" : " (incomplete)"}, ` +
        `accuracy ${pct(s.accuracy)}, false wrong ${pct(s.falseWrong)}, ` +
        `served leaks ${pct(s.leakServed)} (raw ${pct(s.leakRaw)}), ` +
        `schema ${pct(s.schemaValid)}, failures ${s.failures}, ` +
        `p50 ${s.latencyP50} ms, passes ${JSON.stringify(s.passes)}`,
    );
  }
}

if (import.meta.main) await main();
