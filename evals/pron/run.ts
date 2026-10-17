/**
 * Runs the pron_check eval (ADR-0011, docs/07-ai-tutor.md §8).
 *
 *   cd content/tts && uv run --no-sync python ../../evals/pron/make_audio.py
 *   cd evals
 *   deno run -A --env-file=../supabase/functions/.env pron/run.ts \
 *     --models <id>,<id> [--limit <n>]
 *
 * Each case goes the way the app's request goes in the tutor function: the
 * same prompt, schema and guards, the recording as inline audio. It uses
 * the free Gemini quota (one request a case), so tell the user how long it
 * takes and what it uses before running it (CLAUDE.md).
 *
 * Results: `pron/results/<model>.jsonl` keeps one line per case and prompt
 * version, so a run cut short goes on where it stopped;
 * `pron/results/<date>-<model>.<prompt>.json` holds the scores.
 */
import { dirname, fromFileUrl, join } from "@std/path";
import { geminiModel } from "../../supabase/functions/_shared/llm/gemini.ts";
import {
  Cooldown,
  runChain,
} from "../../supabase/functions/_shared/llm/router.ts";
import { llmConfig } from "../../supabase/functions/_shared/llm_config.ts";
import {
  pronCheckPromptVersion,
  pronCheckUserMessage,
} from "../../supabase/functions/_shared/prompts/pron_check.ts";
import type { PronCheckInput } from "../../supabase/functions/_shared/schemas/pron_check.ts";
import {
  parsePronWire,
  pronKitFor,
  pronOutput,
} from "../../supabase/functions/tutor/pron_check.ts";
import { type PronCase, type PronResult, scorePron } from "./score.ts";

const here = dirname(fromFileUrl(import.meta.url));

/** The bytes in base64, a chunk at a time. */
function base64(bytes: Uint8Array): string {
  let text = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    text += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(text);
}

/** Gemini's free tier allows a few requests a minute per model. */
const paceMs = 5_000;

function flag(name: string): string | undefined {
  const index = Deno.args.indexOf(`--${name}`);
  return index >= 0 ? Deno.args[index + 1] : undefined;
}

const apiKey = Deno.env.get(llmConfig.providers.gemini.keyEnv);
if (!apiKey) throw new Error("GEMINI_API_KEY is not set (--env-file)");

// The route is closed until a model passes: candidates are named then.
const models = (flag("models") ?? llmConfig.routes.pron_check.chain.join(","))
  .split(",")
  .filter((id) => id !== "");
if (models.length === 0) throw new Error("name the candidates: --models <id>");
const limit = Number(flag("limit") ?? Infinity);
const cases = (JSON.parse(
  await Deno.readTextFile(join(here, "cases.json")),
) as { cases: PronCase[] }).cases.slice(0, limit);
const kit = pronKitFor("tr-en")!;
const route = llmConfig.routes.pron_check;
const resultsDir = join(here, "results");
await Deno.mkdir(resultsDir, { recursive: true });

for (const id of models) {
  if (llmConfig.models[id]?.audio !== true) {
    throw new Error(`${id} does not hear audio (llm_config.ts)`);
  }
  const model = geminiModel(id, apiKey);
  const file = join(resultsDir, `${id.replaceAll("/", "_")}.jsonl`);
  const done = new Map<string, PronResult>();
  try {
    for (const line of (await Deno.readTextFile(file)).split("\n")) {
      if (!line.trim()) continue;
      const row = JSON.parse(line) as PronResult & { prompt: string };
      if (row.prompt === pronCheckPromptVersion && !row.failure) {
        done.set(row.id, row);
      }
    }
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }

  for (const item of cases) {
    if (done.has(item.id)) continue;
    const wav = await Deno.readFile(join(here, "audio", `${item.id}.wav`));
    const input: PronCheckInput = {
      ctx: { l1: "tr", l2: "en", level: "A1", explain_in: "l1" },
      reference: item.text,
      audio: { data: base64(wav), mime_type: "audio/wav" },
    };
    const started = performance.now();
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
        user: pronCheckUserMessage(input),
        schemaName: "pron_check",
        schema: kit.schema,
        effort: route.effort,
        maxTokens: route.maxTokens,
        timeoutMs: route.timeoutMs,
        audio: { data: input.audio.data, mimeType: "audio/wav" },
      },
      (text) => parsePronWire(kit, text),
    );
    const latencyMs = Math.round(performance.now() - started);
    let row: PronResult;
    if (result.ok) {
      const output = pronOutput(input, result.value, kit, {
        provider: "gemini",
        model: id,
      });
      row = {
        id: item.id,
        model: id,
        uncertain: output.uncertain,
        issues: output.issues.map(({ i, tag, heard }) => ({ i, tag, heard })),
        latencyMs,
      };
    } else {
      row = { id: item.id, model: id, failure: result.code };
    }
    done.set(item.id, row);
    await Deno.writeTextFile(
      file,
      JSON.stringify({ ...row, prompt: pronCheckPromptVersion }) + "\n",
      { append: true },
    );
    console.log(
      `${id} ${item.id}: ${
        row.failure ??
          (row.uncertain
            ? "uncertain"
            : row.issues!.map((x) => `${x.i}:${x.tag}(${x.heard})`).join(" ") ||
              "-")
      }`,
    );
    if (row.failure === "quota_exhausted") break;
    await new Promise((resolve) => setTimeout(resolve, paceMs));
  }

  const score = scorePron(cases, [...done.values()]);
  const date = new Date().toISOString().slice(0, 10);
  await Deno.writeTextFile(
    join(
      resultsDir,
      `${date}-${id.replaceAll("/", "_")}.${pronCheckPromptVersion}.json`,
    ),
    JSON.stringify({ prompt: pronCheckPromptVersion, ...score }, null, 2) +
      "\n",
  );
  console.log(JSON.stringify(score, null, 2));
}
