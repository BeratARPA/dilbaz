/**
 * The ASR bake-off (docs/08-speech.md §3.2): each candidate writes down the
 * recordings of a set, and the set is scored.
 *
 *   cd evals && deno run -A --env-file=../supabase/functions/.env \
 *     asr/run.ts --set <name> [--candidates deepgram,groq,gemini,gemini-ts]
 *
 * Recordings are `asr/audio/<set>/<id>.<wav|m4a|mp3|ogg>`, ids from
 * `dataset.json` (s01…s20 read, f01…f10 free). Free items are scored for
 * WER and fillers when `asr/audio/<set>/refs/<id>.txt` holds what was said,
 * word for word. Transcripts stay next to the audio (outside git, they are
 * the learner's speech); the scores go to `asr/results/<date>-<set>.json`.
 * Each candidate's run resumes where it stopped.
 */
import { join } from "@std/path";
import { deepgramStt } from "../../supabase/functions/_shared/speech/deepgram.ts";
import { type AsrResult, scoreAsr, type ScriptedItem } from "./score.ts";

interface Dataset {
  scripted: ScriptedItem[];
  free: { id: string }[];
}

type Transcribe = (
  bytes: Uint8Array<ArrayBuffer>,
  contentType: string,
) => Promise<{ ok: true; text: string } | { ok: false; failure: string }>;

const types: Record<string, string> = {
  wav: "audio/wav",
  m4a: "audio/mp4",
  mp3: "audio/mpeg",
  ogg: "audio/ogg",
};

function key(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set (--env-file)`);
  return value;
}

/** Deepgram Nova-3 exactly as the app's speech function asks it. */
function deepgram(): Transcribe {
  const stt = deepgramStt(key("DEEPGRAM_API_KEY"));
  return async (bytes, contentType) => {
    const result = await stt.transcribe({ bytes, contentType });
    return result.ok
      ? { ok: true, text: result.transcript.text }
      : { ok: false, failure: result.failure };
  };
}

/** Groq whisper-large-v3 in English, with word times. */
function groq(): Transcribe {
  const apiKey = key("GROQ_API_KEY");
  return async (bytes, contentType) => {
    const form = new FormData();
    const extension = Object.entries(types)
      .find(([, type]) => type === contentType)?.[0] ?? "wav";
    form.append(
      "file",
      new Blob([bytes], { type: contentType }),
      `audio.${extension}`,
    );
    form.append("model", "whisper-large-v3");
    form.append("language", "en");
    form.append("response_format", "verbose_json");
    form.append("timestamp_granularities[]", "word");
    form.append("temperature", "0");
    const response = await fetch(
      "https://api.groq.com/openai/v1/audio/transcriptions",
      {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}` },
        body: form,
      },
    );
    if (!response.ok) {
      const body = await response.text();
      return {
        ok: false,
        failure: response.status === 429 ? "quota" : `http_${response.status}`,
        ...(body.includes("per day") ? { failure: "quota" } : {}),
      };
    }
    const body = await response.json() as { text?: string };
    return { ok: true, text: (body.text ?? "").trim() };
  };
}

/**
 * Gemini 3.5 Transcribe, verbatim (fillers, repetitions and false starts
 * kept); with word times or without, which the documentation says costs
 * some accuracy (checked 2026-10-17).
 */
function gemini(withTimes: boolean): Transcribe {
  const apiKey = key("GEMINI_API_KEY");
  return async (bytes, contentType) => {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 0x8000) {
      binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    }
    const response = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/interactions",
      {
        method: "POST",
        headers: {
          "x-goog-api-key": apiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gemini-3.5-transcribe",
          input: [{
            type: "audio",
            data: btoa(binary),
            mime_type: contentType,
          }],
          generation_config: {
            transcription_config: {
              mode: withTimes
                ? { type: "verbatim", timestamp_granularities: ["word"] }
                : { type: "verbatim" },
            },
          },
        }),
      },
    );
    if (!response.ok) {
      const body = await response.text();
      if (response.status !== 429) {
        return { ok: false, failure: `http_${response.status}` };
      }
      return {
        ok: false,
        failure: body.includes("per minute") ? "rate" : "quota",
      };
    }
    const body = await response.json() as {
      output_text?: string;
      steps?: { type?: string; content?: { type?: string; text?: string }[] }[];
    };
    const text = body.output_text ?? (body.steps ?? [])
      .filter((step) => step.type === "model_output")
      .flatMap((step) => step.content ?? [])
      .filter((part) => part.type === "text")
      .map((part) => part.text ?? "")
      .join(" ");
    return { ok: true, text: text.trim() };
  };
}

const candidates: Record<string, { make: () => Transcribe; paceMs: number }> = {
  deepgram: { make: deepgram, paceMs: 0 },
  groq: { make: groq, paceMs: 3_000 },
  // The free tier allows 3 requests a minute (2026-10-17).
  gemini: { make: () => gemini(false), paceMs: 21_000 },
  "gemini-ts": { make: () => gemini(true), paceMs: 21_000 },
};

function arg(name: string): string | undefined {
  const at = Deno.args.indexOf(`--${name}`);
  return at < 0 ? undefined : Deno.args[at + 1];
}

async function readLines(path: string): Promise<AsrResult[]> {
  try {
    return (await Deno.readTextFile(path))
      .split("\n")
      .filter((line) => line.trim() !== "")
      .map((line) => JSON.parse(line) as AsrResult);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return [];
    throw error;
  }
}

async function main() {
  const set = arg("set");
  if (!set) {
    console.error("usage: asr/run.ts --set <name> [--candidates a,b]");
    Deno.exit(2);
  }
  const here = new URL(".", import.meta.url).pathname.replace(/^\/(\w:)/, "$1");
  const dataset = JSON.parse(
    await Deno.readTextFile(join(here, "dataset.json")),
  ) as Dataset;
  const folder = join(here, "audio", set);
  const recordings = new Map<string, string>();
  for await (const entry of Deno.readDir(folder)) {
    const match = entry.name.match(/^([sf]\d\d)\.(\w+)$/);
    if (entry.isFile && match && types[match[2]]) {
      recordings.set(match[1], entry.name);
    }
  }
  const references = new Map<string, string>();
  for (const { id } of dataset.free) {
    try {
      references.set(
        id,
        await Deno.readTextFile(join(folder, "refs", `${id}.txt`)),
      );
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }
  const scripted = dataset.scripted.filter((item) => recordings.has(item.id));
  const names = (arg("candidates") ?? Object.keys(candidates).join(","))
    .split(",");
  const scores = [];
  await Deno.mkdir(join(folder, "transcripts"), { recursive: true });
  for (const name of names) {
    const candidate = candidates[name];
    if (!candidate) throw new Error(`unknown candidate ${name}`);
    const path = join(folder, "transcripts", `${name}.jsonl`);
    const done = await readLines(path);
    const finished = new Set(
      done.filter((r) => r.text !== undefined).map((r) => r.id),
    );
    const transcribe = candidate.make();
    let stopped = false;
    for (const [id, file] of [...recordings].sort()) {
      if (finished.has(id)) continue;
      const bytes = await Deno.readFile(join(folder, file));
      const contentType = types[file.split(".").at(-1)!];
      let started = performance.now();
      let result = await transcribe(bytes, contentType);
      // A per-minute limit passes: wait it out, twice at most.
      for (
        let tries = 0;
        !result.ok && result.failure === "rate" && tries < 2;
        tries++
      ) {
        await new Promise((resolve) => setTimeout(resolve, 61_000));
        started = performance.now();
        result = await transcribe(bytes, contentType);
      }
      const line: AsrResult = result.ok
        ? {
          id,
          candidate: name,
          text: result.text,
          latencyMs: Math.round(performance.now() - started),
        }
        : { id, candidate: name, failure: result.failure };
      await Deno.writeTextFile(path, JSON.stringify(line) + "\n", {
        append: true,
      });
      console.log(`${name} ${id}: ${result.ok ? "ok" : result.failure}`);
      if (!result.ok && result.failure === "quota") {
        stopped = true;
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, candidate.paceMs));
    }
    const latest = new Map<string, AsrResult>();
    for (const result of await readLines(path)) {
      if (result.text !== undefined || !latest.has(result.id)) {
        latest.set(result.id, result);
      }
    }
    const score = scoreAsr(name, scripted, [...latest.values()], references);
    console.log(JSON.stringify({ ...score, complete: !stopped }));
    scores.push({ ...score, complete: !stopped });
  }
  const day = new Date().toISOString().slice(0, 10);
  await Deno.mkdir(join(here, "results"), { recursive: true });
  // The day's scores of this set, the latest of each candidate.
  const path = join(here, "results", `${day}-${set}.json`);
  let earlier: { candidate: string }[] = [];
  try {
    earlier = JSON.parse(await Deno.readTextFile(path)).scores;
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  const merged = [
    ...earlier.filter((s) => !names.includes(s.candidate)),
    ...scores,
  ].sort((a, b) => a.candidate.localeCompare(b.candidate));
  await Deno.writeTextFile(
    path,
    JSON.stringify(
      { set, recordings: recordings.size, scores: merged },
      null,
      2,
    ) + "\n",
  );
}

if (import.meta.main) await main();
