import { assert, assertEquals } from "@std/assert";
import { deepgramStt, failureOf } from "./deepgram.ts";

const audio = { bytes: new Uint8Array([1, 2, 3]), contentType: "audio/mp4" };

/** A fetch that answers once and remembers the request. */
function fakeFetch(answer: () => Response) {
  const seen: { url: string; init: RequestInit }[] = [];
  const fetcher = (input: string | URL | Request, init?: RequestInit) => {
    seen.push({ url: String(input), init: init ?? {} });
    return Promise.resolve(answer());
  };
  return { fetcher: fetcher as typeof fetch, seen };
}

const body = {
  metadata: { duration: 1.6 },
  results: {
    channels: [{
      alternatives: [{
        transcript: "uh he go to work",
        words: [
          { word: "uh", start: 0.08, end: 0.2, confidence: 0.9 },
          { word: "he", start: 0.3, end: 0.45, confidence: 0.99 },
          { word: "go", start: 0.45, end: 0.7, confidence: 0.98 },
          { word: "to", start: 0.7, end: 0.8, confidence: 0.99 },
          { word: "work", start: 0.8, end: 1.2345, confidence: 0.97 },
        ],
      }],
    }],
  },
};

Deno.test("asks for verbatim English and keeps the learner's words", async () => {
  const { fetcher, seen } = fakeFetch(() => Response.json(body));

  const result = await deepgramStt("test-key", fetcher).transcribe(audio);

  assert(result.ok);
  assertEquals(result.transcript.text, "uh he go to work");
  assertEquals(result.transcript.words[4], {
    w: "work",
    startMs: 800,
    endMs: 1235,
    conf: 0.97,
  });
  assertEquals(result.transcript.durationMs, 1600);
  assertEquals(result.transcript.provider, "deepgram");
  assertEquals(result.transcript.model, "nova-3");

  const [{ url, init }] = seen;
  const params = new URL(url).searchParams;
  assertEquals(
    new URL(url).origin + new URL(url).pathname,
    "https://api.deepgram.com/v1/listen",
  );
  assertEquals(params.get("model"), "nova-3");
  assertEquals(params.get("language"), "en");
  assertEquals(params.get("filler_words"), "true");
  assertEquals(params.get("smart_format"), "false");
  assertEquals(params.get("punctuate"), "false");
  assertEquals(params.get("mip_opt_out"), "true");
  const headers = new Headers(init.headers);
  assertEquals(headers.get("authorization"), "Token test-key");
  assertEquals(headers.get("content-type"), "audio/mp4");
  assertEquals(init.method, "POST");
  assertEquals(init.body, audio.bytes);
});

Deno.test("silence is an empty transcript", async () => {
  const { fetcher } = fakeFetch(() =>
    Response.json({ metadata: { duration: 0.5 }, results: { channels: [] } })
  );

  const result = await deepgramStt("k", fetcher).transcribe(audio);

  assert(result.ok);
  assertEquals(result.transcript.text, "");
  assertEquals(result.transcript.words, []);
  assertEquals(result.transcript.durationMs, 500);
});

Deno.test("refusals map to failures", async () => {
  for (
    const [status, failure] of [
      [400, "bad_audio"],
      [401, "provider_auth"],
      [402, "provider_quota"],
      [429, "provider_busy"],
      [503, "provider_error"],
    ] as const
  ) {
    const { fetcher } = fakeFetch(() =>
      new Response(JSON.stringify({ err_code: "x" }), { status })
    );
    const result = await deepgramStt("k", fetcher).transcribe(audio);
    assertEquals(result, { ok: false, failure }, String(status));
  }
  assertEquals(failureOf(403), "provider_auth");
  assertEquals(failureOf(413), "bad_audio");
});

Deno.test("no connection is a network failure", async () => {
  const fetcher =
    (() => Promise.reject(new TypeError("offline"))) as typeof fetch;

  const result = await deepgramStt("k", fetcher).transcribe(audio);

  assertEquals(result, { ok: false, failure: "network" });
});
