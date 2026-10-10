import { assert, assertEquals } from "@std/assert";
import type { AuthOutcome, UserVerifier } from "../_shared/auth.ts";
import type {
  SpeechToText,
  SttResult,
  Transcript,
} from "../_shared/speech/types.ts";
import {
  createSpeechHandler,
  routeOf,
  type SpeechUsage,
  sttCost,
} from "./handler.ts";

const userId = "0192f5a0-0000-7000-8000-000000000001";
const signedIn: UserVerifier = () =>
  Promise.resolve<AuthOutcome>({ ok: true, userId });
const signedOut: UserVerifier = () =>
  Promise.resolve<AuthOutcome>({
    ok: false,
    status: 401,
    code: "MISSING_CREDENTIALS",
  });

const transcript: Transcript = {
  text: "he go to work",
  words: [{ w: "he", startMs: 0, endMs: 200 }],
  provider: "deepgram",
  model: "nova-3",
  durationMs: 3000,
};

function recognizer(result: SttResult = { ok: true, transcript }) {
  const heard: Uint8Array[] = [];
  const stt: SpeechToText = {
    provider: "deepgram",
    transcribe: (audio) => {
      heard.push(audio.bytes);
      return Promise.resolve(result);
    },
  };
  return { stt, heard };
}

function setup(
  options: {
    verifyUser?: UserVerifier;
    english?: SpeechToText | null;
    turkish?: SpeechToText | null;
    recordUsage?: (usage: SpeechUsage) => Promise<void>;
  } = {},
) {
  const lines: string[] = [];
  const usage: SpeechUsage[] = [];
  const handle = createSpeechHandler({
    verifyUser: options.verifyUser ?? signedIn,
    english: options.english === undefined ? recognizer().stt : options.english,
    turkish: options.turkish === undefined ? null : options.turkish,
    recordUsage: options.recordUsage ??
      ((row) => {
        usage.push(row);
        return Promise.resolve();
      }),
    logSink: (line) => lines.push(line),
  });
  return { handle, lines, usage };
}

const url = "http://localhost:54321/functions/v1/speech/transcribe";

function audio(
  bytes = new Uint8Array([1, 2, 3, 4]),
  type = "audio/mp4",
  query = "",
): Request {
  return new Request(url + query, {
    method: "POST",
    headers: { "Content-Type": type },
    body: bytes,
  });
}

Deno.test("transcribes the audio in the body and records the use", async () => {
  const { stt, heard } = recognizer();
  const { handle, usage } = setup({ english: stt });

  const response = await handle(audio());

  assertEquals(response.status, 200);
  assertEquals(await response.json(), transcript);
  assertEquals(heard, [new Uint8Array([1, 2, 3, 4])]);
  assertEquals(usage, [{
    profileId: userId,
    provider: "deepgram",
    kind: "stt",
    seconds: 3,
    costUsd: sttCost(3),
  }]);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("a transcript never reaches the logs", async () => {
  const { handle, lines } = setup();

  await handle(audio());

  assertEquals(lines.length, 1);
  const line = JSON.parse(lines[0]);
  assertEquals(line.fn, "speech");
  assertEquals(line.route, "transcribe");
  assertEquals(line.status, 200);
  assertEquals(line.model, "nova-3");
  assert(!lines[0].includes("work"));
});

Deno.test("only signed-in users are heard", async () => {
  const { stt, heard } = recognizer();
  const { handle } = setup({ verifyUser: signedOut, english: stt });

  const response = await handle(audio());

  assertEquals(response.status, 401);
  assertEquals(heard, []);
});

Deno.test("routes and methods are checked before anything else", async () => {
  const { handle } = setup();
  const unknown = await handle(
    new Request("http://localhost:54321/functions/v1/speech/assess", {
      method: "POST",
    }),
  );
  assertEquals(unknown.status, 404);
  const get = await handle(new Request(url));
  assertEquals(get.status, 405);
  const options = await handle(new Request(url, { method: "OPTIONS" }));
  assertEquals(options.status, 204);
  assertEquals(routeOf("http://x/functions/v1/speech"), null);
});

Deno.test("Turkish goes to its own recognizer, free of charge", async () => {
  const turkish: Transcript = {
    text: "Bulaşıkları ben yıkarım.",
    words: [],
    provider: "groq",
    model: "whisper-large-v3",
    durationMs: 2000,
  };
  const english = recognizer();
  const { stt, heard } = recognizer({ ok: true, transcript: turkish });
  const { handle, usage } = setup({ english: english.stt, turkish: stt });

  const response = await handle(audio(undefined, undefined, "?lang=tr"));

  assertEquals(response.status, 200);
  assertEquals((await response.json()).text, "Bulaşıkları ben yıkarım.");
  assertEquals(heard.length, 1);
  assertEquals(english.heard.length, 0);
  assertEquals(usage[0].provider, "groq");
  assertEquals(usage[0].costUsd, 0);
});

Deno.test("other languages, or Turkish without its key, are not heard", async () => {
  const { handle } = setup();
  const other = await handle(audio(undefined, undefined, "?lang=de"));
  assertEquals(other.status, 400);
  assertEquals(await other.json(), { error: { code: "unsupported_language" } });
  const turkish = await handle(audio(undefined, undefined, "?lang=tr"));
  assertEquals(turkish.status, 503);
  assertEquals(await turkish.json(), { error: { code: "stt_unavailable" } });
});

Deno.test("without its key the recognizer is unavailable", async () => {
  const { handle } = setup({ english: null });
  const response = await handle(audio());
  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: { code: "stt_unavailable" } });
});

Deno.test("only audio of the known types and sizes is taken", async () => {
  const { handle } = setup();
  assertEquals((await handle(audio(undefined, "text/plain"))).status, 415);
  assertEquals((await handle(audio(new Uint8Array()))).status, 400);
  const big = new Uint8Array(2 * 1024 * 1024 + 1);
  assertEquals((await handle(audio(big))).status, 413);
  // A media type with parameters is still that type.
  assertEquals(
    (await handle(audio(undefined, "audio/webm; codecs=opus"))).status,
    200,
  );
});

Deno.test("provider failures become stable codes", async () => {
  for (
    const [failure, status, code] of [
      ["bad_audio", 422, "bad_audio"],
      ["provider_auth", 503, "stt_unavailable"],
      ["provider_quota", 503, "stt_quota"],
      ["provider_busy", 503, "stt_busy"],
      ["provider_error", 502, "stt_failed"],
      ["network", 502, "stt_failed"],
    ] as const
  ) {
    const { stt } = recognizer({ ok: false, failure });
    const { handle, usage, lines } = setup({ english: stt });
    const response = await handle(audio());
    assertEquals(response.status, status, failure);
    assertEquals(await response.json(), { error: { code } });
    assertEquals(usage, []);
    // The log keeps the provider's own reason.
    assertEquals(JSON.parse(lines[0]).code, failure);
  }
});

Deno.test("a usage row that cannot be written does not cost the transcript", async () => {
  const { handle, lines } = setup({
    recordUsage: () => Promise.reject(new Error("db")),
  });

  const response = await handle(audio());

  assertEquals(response.status, 200);
  assert(lines.some((line) => JSON.parse(line).event === "usage_not_recorded"));
});

Deno.test("the Deepgram credit is spent by the minute", () => {
  assertEquals(sttCost(60), 0.0043);
  assertEquals(sttCost(3), 0.000215);
  assertEquals(sttCost(0), 0);
});
