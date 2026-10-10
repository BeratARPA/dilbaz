import { assert, assertEquals } from "@std/assert";
import { groqFailureOf, groqStt } from "./groq_stt.ts";

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

Deno.test("sends the audio as a Turkish Whisper transcription", async () => {
  const { fetcher, seen } = fakeFetch(() =>
    Response.json({
      text: " Bulaşıkları ben yıkarım. ",
      duration: 2.4,
      segments: [{ end: 2.3 }],
      x_groq: { id: "req_1" },
    })
  );

  const result = await groqStt("test-key", fetcher).transcribe(audio);

  assert(result.ok);
  assertEquals(result.transcript, {
    text: "Bulaşıkları ben yıkarım.",
    words: [],
    provider: "groq",
    model: "whisper-large-v3",
    durationMs: 2400,
  });
  const [{ url, init }] = seen;
  assertEquals(url, "https://api.groq.com/openai/v1/audio/transcriptions");
  assertEquals(
    (init.headers as Record<string, string>).Authorization,
    "Bearer test-key",
  );
  const form = init.body as FormData;
  assertEquals(form.get("model"), "whisper-large-v3");
  assertEquals(form.get("language"), "tr");
  assertEquals(form.get("response_format"), "verbose_json");
  const file = form.get("file") as File;
  assertEquals(file.name, "audio.m4a");
  assertEquals(new Uint8Array(await file.arrayBuffer()), audio.bytes);
});

Deno.test("without a duration the last segment tells the length", async () => {
  const { fetcher } = fakeFetch(() =>
    Response.json({ text: "merhaba", segments: [{ end: 0.5 }, { end: 1.25 }] })
  );
  const result = await groqStt("k", fetcher).transcribe({
    ...audio,
    contentType: "audio/webm",
  });
  assert(result.ok);
  assertEquals(result.transcript.durationMs, 1250);
});

Deno.test("refusals map to failures, a spent day to the quota", () => {
  const status = (code: number, headers: HeadersInit = {}) =>
    groqFailureOf(new Response(null, { status: code, headers }));
  assertEquals(status(400), "bad_audio");
  assertEquals(status(413), "bad_audio");
  assertEquals(status(401), "provider_auth");
  assertEquals(status(429), "provider_busy");
  assertEquals(
    status(429, { "x-ratelimit-remaining-requests": "0" }),
    "provider_quota",
  );
  // The day's audio seconds are gone while requests are left.
  const requestsLeft = new Response(null, {
    status: 429,
    headers: { "x-ratelimit-remaining-requests": "1900" },
  });
  assertEquals(
    groqFailureOf(
      requestsLeft,
      '{"error":{"message":"Rate limit reached for model ' +
        "`whisper-large-v3` on audio seconds per day (ASD): Limit 28800, " +
        'Used 28790, Requested 30."}}',
    ),
    "provider_quota",
  );
  // An hour's limit passes.
  assertEquals(
    groqFailureOf(requestsLeft, "... on audio seconds per hour (ASH) ..."),
    "provider_busy",
  );
  assertEquals(status(498), "provider_busy");
  assertEquals(status(500), "provider_error");
});

Deno.test("a refused request and no connection are failures", async () => {
  const refused = fakeFetch(() => new Response("{}", { status: 401 }));
  assertEquals(
    await groqStt("k", refused.fetcher).transcribe(audio),
    { ok: false, failure: "provider_auth" },
  );
  const offline =
    (() => Promise.reject(new TypeError("offline"))) as typeof fetch;
  assertEquals(
    await groqStt("k", offline).transcribe(audio),
    { ok: false, failure: "network" },
  );
});
