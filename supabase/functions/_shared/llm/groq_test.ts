import { assert, assertEquals } from "@std/assert";
import { groqFailure, groqModel } from "./groq.ts";
import type { LlmRequest } from "./types.ts";

const request: LlmRequest = {
  system: "You check answers.",
  user: '{"response":"he go"}',
  schemaName: "answer_check",
  schema: { type: "object", additionalProperties: false },
  effort: "low",
  maxTokens: 4000,
  timeoutMs: 1000,
};

function fakeFetch(answer: () => Response) {
  const seen: { url: string; init: RequestInit }[] = [];
  const fetcher = (input: string | URL | Request, init?: RequestInit) => {
    seen.push({ url: String(input), init: init ?? {} });
    return Promise.resolve(answer());
  };
  return { fetcher: fetcher as typeof fetch, seen };
}

Deno.test("asks for strict JSON with low reasoning and no reasoning text", async () => {
  const { fetcher, seen } = fakeFetch(() =>
    Response.json({
      choices: [{
        message: { content: '{"verdict":"correct"}' },
        finish_reason: "stop",
      }],
      usage: {
        prompt_tokens: 4641,
        completion_tokens: 310,
        prompt_tokens_details: { cached_tokens: 4608 },
      },
    })
  );

  const outcome = await groqModel("oss-test", "test-key", fetcher)
    .generate(request);

  assert(outcome.ok);
  assertEquals(outcome.text, '{"verdict":"correct"}');
  assertEquals(outcome.usage, {
    inputTokens: 4641,
    outputTokens: 310,
    cachedTokens: 4608,
  });

  const [{ url, init }] = seen;
  assertEquals(url, "https://api.groq.com/openai/v1/chat/completions");
  assertEquals(
    new Headers(init.headers).get("Authorization"),
    "Bearer test-key",
  );
  const body = JSON.parse(String(init.body));
  assertEquals(body.model, "oss-test");
  assertEquals(body.messages, [
    { role: "system", content: "You check answers." },
    { role: "user", content: '{"response":"he go"}' },
  ]);
  assertEquals(body.response_format, {
    type: "json_schema",
    json_schema: {
      name: "answer_check",
      strict: true,
      schema: { type: "object", additionalProperties: false },
    },
  });
  assertEquals(body.reasoning_effort, "low");
  assertEquals(body.include_reasoning, false);
  assertEquals(body.max_completion_tokens, 4000);
});

Deno.test("a cut answer and a filtered one are failures", async () => {
  for (
    const [finish, failure] of [["length", "length"], [
      "content_filter",
      "refused",
    ]]
  ) {
    const { fetcher } = fakeFetch(() =>
      Response.json({
        choices: [{ message: { content: "{" }, finish_reason: finish }],
      })
    );
    const outcome = await groqModel("m", "k", fetcher).generate(request);
    assert(!outcome.ok);
    assertEquals(outcome.failure, failure);
  }
});

Deno.test("429 tells the daily limit from the per-minute one", async () => {
  const { fetcher } = fakeFetch(() =>
    new Response("{}", {
      status: 429,
      headers: { "retry-after": "7", "x-ratelimit-remaining-requests": "12" },
    })
  );
  const outcome = await groqModel("m", "k", fetcher).generate(request);
  assert(!outcome.ok);
  assertEquals(outcome.failure, "busy");
  assertEquals(outcome.retryAfterMs, 7000);

  const spent = new Headers({ "x-ratelimit-remaining-requests": "0" });
  assertEquals(groqFailure(429, spent, ""), "quota");

  // The day's tokens are gone while requests are left (seen 2026-10-08).
  const requestsLeft = new Headers({
    "retry-after": "1325",
    "x-ratelimit-remaining-requests": "990",
  });
  assertEquals(
    groqFailure(
      429,
      requestsLeft,
      '{"error":{"message":"Rate limit reached for model ' +
        "`openai/gpt-oss-120b` on tokens per day (TPD): Limit 200000, " +
        'Used 197583, Requested 5482. Please try again in 22m4.08s."}}',
    ),
    "quota",
  );
});

Deno.test("statuses map to failures", () => {
  const none = new Headers();
  assertEquals(
    groqFailure(400, none, '{"error":{"code":"json_validate_failed"}}'),
    "invalid",
  );
  assertEquals(groqFailure(400, none, "{}"), "bad_request");
  assertEquals(groqFailure(404, none, ""), "bad_request");
  assertEquals(groqFailure(422, none, ""), "bad_request");
  assertEquals(groqFailure(401, none, ""), "auth");
  assertEquals(groqFailure(503, none, ""), "busy");
  assertEquals(groqFailure(500, none, ""), "server");
});
