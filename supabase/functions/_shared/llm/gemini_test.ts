import { assert, assertEquals } from "@std/assert";
import { geminiFailure, geminiModel } from "./gemini.ts";
import type { LlmRequest } from "./types.ts";

const request: LlmRequest = {
  system: "You check answers.",
  user: '{"response":"he go"}',
  schemaName: "answer_check",
  schema: { type: "object" },
  effort: "low",
  maxTokens: 4000,
  timeoutMs: 1000,
};

/** A fetch that answers once and remembers the request. */
function fakeFetch(answer: () => Response | Promise<Response>) {
  const seen: { url: string; init: RequestInit }[] = [];
  const fetcher = (input: string | URL | Request, init?: RequestInit) => {
    seen.push({ url: String(input), init: init ?? {} });
    return Promise.resolve(answer());
  };
  return { fetcher: fetcher as typeof fetch, seen };
}

const answered = {
  candidates: [{
    content: {
      parts: [
        { text: "thinking about it", thought: true },
        { text: '{"verdict":' },
        { text: '"correct"}' },
      ],
    },
    finishReason: "STOP",
  }],
  usageMetadata: {
    promptTokenCount: 3200,
    candidatesTokenCount: 120,
    thoughtsTokenCount: 80,
    cachedContentTokenCount: 3000,
  },
};

Deno.test("sends the prompt, the schema and the thinking level", async () => {
  const { fetcher, seen } = fakeFetch(() => Response.json(answered));

  const outcome = await geminiModel("gemini-test", "test-key", fetcher)
    .generate(request);

  assert(outcome.ok);
  assertEquals(outcome.text, '{"verdict":"correct"}');
  assertEquals(outcome.usage, {
    inputTokens: 3200,
    outputTokens: 200,
    cachedTokens: 3000,
  });
  assertEquals(outcome.stopReason, "stop");

  const [{ url, init }] = seen;
  assertEquals(
    url,
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent",
  );
  const headers = new Headers(init.headers);
  assertEquals(headers.get("x-goog-api-key"), "test-key");
  const body = JSON.parse(String(init.body));
  assertEquals(body.systemInstruction, {
    parts: [{ text: "You check answers." }],
  });
  assertEquals(body.contents, [{
    role: "user",
    parts: [{ text: '{"response":"he go"}' }],
  }]);
  assertEquals(body.generationConfig, {
    responseMimeType: "application/json",
    responseJsonSchema: { type: "object" },
    maxOutputTokens: 4000,
    thinkingConfig: { thinkingLevel: "LOW" },
  });
  assert(init.signal instanceof AbortSignal, "every call has a timeout");
});

Deno.test("a recording goes before the text as inline data", async () => {
  const { fetcher, seen } = fakeFetch(() => Response.json(answered));
  await geminiModel("gemini-test", "test-key", fetcher).generate({
    ...request,
    audio: { data: "UklGRg==", mimeType: "audio/wav" },
  });
  const body = JSON.parse(String(seen[0].init.body));
  assertEquals(body.contents[0].parts, [
    { inlineData: { mimeType: "audio/wav", data: "UklGRg==" } },
    { text: '{"response":"he go"}' },
  ]);
});

Deno.test("a cut answer, a block and a refusal are failures", async () => {
  const cases: [unknown, string][] = [
    [{ candidates: [{ finishReason: "MAX_TOKENS" }] }, "length"],
    [{ candidates: [{ finishReason: "SAFETY" }] }, "refused"],
    [{ promptFeedback: { blockReason: "OTHER" } }, "refused"],
    [{ candidates: [] }, "refused"],
  ];
  for (const [body, failure] of cases) {
    const { fetcher } = fakeFetch(() => Response.json(body));
    const outcome = await geminiModel("m", "k", fetcher).generate(request);
    assert(!outcome.ok);
    assertEquals(outcome.failure, failure, JSON.stringify(body));
  }
});

Deno.test("a spent daily quota is told apart from a per-minute limit", async () => {
  const daily = {
    error: {
      code: 429,
      status: "RESOURCE_EXHAUSTED",
      details: [
        {
          "@type": "type.googleapis.com/google.rpc.QuotaFailure",
          violations: [{
            quotaId: "GenerateRequestsPerDayPerProjectPerModel-FreeTier",
          }],
        },
        {
          "@type": "type.googleapis.com/google.rpc.RetryInfo",
          retryDelay: "41s",
        },
      ],
    },
  };
  const { fetcher } = fakeFetch(() => Response.json(daily, { status: 429 }));
  const outcome = await geminiModel("m", "k", fetcher).generate(request);
  assert(!outcome.ok);
  assertEquals(outcome.failure, "quota");
  assertEquals(outcome.retryAfterMs, 41_000);

  assertEquals(geminiFailure(429, '{"error":{"details":[]}}'), "busy");
  assertEquals(geminiFailure(401, ""), "auth");
  assertEquals(geminiFailure(403, ""), "auth");
  assertEquals(geminiFailure(400, ""), "bad_request");
  assertEquals(geminiFailure(404, ""), "bad_request");
  assertEquals(geminiFailure(503, ""), "busy");
  assertEquals(geminiFailure(500, ""), "server");
});

Deno.test("no connection and no answer in time are failures", async () => {
  const offline =
    (() => Promise.reject(new TypeError("offline"))) as typeof fetch;
  const lost = await geminiModel("m", "k", offline).generate(request);
  assert(!lost.ok);
  assertEquals(lost.failure, "network");

  const slow =
    ((_: unknown, init?: RequestInit) =>
      new Promise<Response>((_, reject) =>
        init?.signal?.addEventListener(
          "abort",
          () => reject(init.signal?.reason),
        )
      )) as typeof fetch;
  const late = await geminiModel("m", "k", slow).generate({
    ...request,
    timeoutMs: 10,
  });
  assert(!late.ok);
  assertEquals(late.failure, "timeout");
});
