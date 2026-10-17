import { assert, assertEquals } from "@std/assert";
import { type ChainDeps, Cooldown, runChain } from "./router.ts";
import type { LlmModel, LlmOutcome, LlmRequest } from "./types.ts";

const request: LlmRequest = {
  system: "s",
  user: "u",
  schemaName: "answer_check",
  schema: {},
  effort: "low",
  maxTokens: 4000,
  timeoutMs: 1000,
};

const usage = { inputTokens: 100, outputTokens: 20, cachedTokens: 0 };
const good: LlmOutcome = { ok: true, text: "good", usage, stopReason: "stop" };
const bad: LlmOutcome = { ok: true, text: "bad", usage, stopReason: "stop" };
const fail = (
  failure: Extract<LlmOutcome, { ok: false }>["failure"],
  retryAfterMs?: number,
): LlmOutcome => ({ ok: false, failure, retryAfterMs });

/** A model that answers with [outcomes] in turn and remembers requests. */
function model(
  id: string,
  provider: "gemini" | "groq",
  ...outcomes: LlmOutcome[]
) {
  const asked: LlmRequest[] = [];
  const fake: LlmModel = {
    id,
    provider,
    generate(req) {
      asked.push(req);
      return Promise.resolve(outcomes.shift() ?? fail("server"));
    },
  };
  return { fake, asked };
}

const lite = "gemini-3.1-flash-lite";
const oss = "openai/gpt-oss-120b";
const accept = (text: string) => (text === "good" ? "judged" : null);

function deps(overrides: Partial<ChainDeps> = {}): ChainDeps {
  let clock = 1_000_000;
  return {
    models: [],
    consent: true,
    use: new Map(),
    cooldown: new Cooldown(),
    now: () => (clock += 50),
    ...overrides,
  };
}

Deno.test("the primary model answers", async () => {
  const primary = model(lite, "gemini", good);
  const fallback = model(oss, "groq", good);

  const result = await runChain(
    deps({ models: [primary.fake, fallback.fake] }),
    request,
    accept,
  );

  assert(result.ok);
  assertEquals(result.value, "judged");
  assertEquals(result.model.id, lite);
  assertEquals(fallback.asked.length, 0);
  assertEquals(result.calls, [{
    provider: "gemini",
    model: lite,
    inputTokens: 100,
    outputTokens: 20,
    cachedTokens: 0,
    stopReason: "stop",
    latencyMs: 50,
  }]);
});

Deno.test("without the data consent Gemini is not asked (ADR-0009)", async () => {
  const primary = model(lite, "gemini", good);
  const fallback = model(oss, "groq", good);

  const result = await runChain(
    deps({ models: [primary.fake, fallback.fake], consent: false }),
    request,
    accept,
  );

  assert(result.ok);
  assertEquals(result.model.id, oss);
  assertEquals(primary.asked.length, 0);
});

Deno.test("past the learner's half of a quota, the next model answers", async () => {
  const primary = model(lite, "gemini", good);
  const fallback = model(oss, "groq", good);

  const result = await runChain(
    deps({
      models: [primary.fake, fallback.fake],
      use: new Map([[lite, { requests: 250, tokens: 0 }]]),
    }),
    request,
    accept,
  );

  assert(result.ok);
  assertEquals(result.model.id, oss);
  assertEquals(primary.asked.length, 0);
});

Deno.test("when every share is spent, the answer is quota_exhausted", async () => {
  const primary = model(lite, "gemini", good);
  const fallback = model(oss, "groq", good);

  const result = await runChain(
    deps({
      models: [primary.fake, fallback.fake],
      use: new Map([
        [lite, { requests: 250, tokens: 0 }],
        [oss, { requests: 0, tokens: 100_000 }],
      ]),
    }),
    request,
    accept,
  );

  assert(!result.ok);
  assertEquals(result.code, "quota_exhausted");
  assertEquals(result.calls, []);
});

Deno.test("an invalid answer is asked for once more", async () => {
  const primary = model(lite, "gemini", bad, good);

  const result = await runChain(
    deps({ models: [primary.fake] }),
    request,
    accept,
  );

  assert(result.ok);
  assertEquals(result.calls.map((c) => c.stopReason), ["invalid", "stop"]);
});

Deno.test("two invalid answers move on to the next model", async () => {
  const primary = model(lite, "gemini", bad, bad, good);
  const fallback = model(oss, "groq", good);

  const result = await runChain(
    deps({ models: [primary.fake, fallback.fake] }),
    request,
    accept,
  );

  assert(result.ok);
  assertEquals(result.model.id, oss);
  assertEquals(primary.asked.length, 2);
});

Deno.test("a cut answer is asked again with twice the ceiling", async () => {
  const primary = model(lite, "gemini", fail("length"), good);

  const result = await runChain(
    deps({ models: [primary.fake] }),
    request,
    accept,
  );

  assert(result.ok);
  assertEquals(primary.asked.map((r) => r.maxTokens), [4000, 8000]);
});

Deno.test("a 429 cools the model down: until the quota day ends, or for a while", async () => {
  const cooldown = new Cooldown();
  let clock = Date.parse("2026-09-30T10:00:00Z");
  const now = () => clock;

  const spent = model(lite, "gemini", fail("quota"));
  const busy = model(oss, "groq", fail("busy", 7000));
  const result = await runChain(
    deps({ models: [spent.fake, busy.fake], cooldown, now }),
    request,
    accept,
  );
  assert(!result.ok);
  assertEquals(result.code, "llm_failed");

  // Gemini's day ends at midnight Pacific time: 07:00 UTC in summer.
  clock = Date.parse("2026-10-01T06:59:00Z");
  assertEquals(cooldown.blocked(lite, clock), "quota");
  assertEquals(cooldown.blocked(oss, clock), null);
  clock = Date.parse("2026-09-30T10:00:06Z");
  assertEquals(
    cooldown.blocked(oss, clock),
    "busy",
    "still within the 7 s asked for",
  );

  // A spent quota is skipped like a spent share.
  const again = await runChain(
    deps({ models: [model(lite, "gemini", good).fake], cooldown, now }),
    request,
    accept,
  );
  assert(!again.ok);
  assertEquals(again.code, "quota_exhausted");

  // A busy model is not a day's share spent: the learner hears "not now".
  const soon = await runChain(
    deps({ models: [model(oss, "groq", good).fake], cooldown, now }),
    request,
    accept,
  );
  assert(!soon.ok);
  assertEquals(soon.code, "llm_failed");
});

Deno.test("refusals everywhere read as llm_refused, other failures as llm_failed", async () => {
  const refused = await runChain(
    deps({
      models: [
        model(lite, "gemini", fail("refused")).fake,
        model(oss, "groq", fail("refused")).fake,
      ],
    }),
    request,
    accept,
  );
  assert(!refused.ok);
  assertEquals(refused.code, "llm_refused");
  assertEquals(refused.calls.map((c) => c.stopReason), ["refused", "refused"]);

  const failed = await runChain(
    deps({
      models: [
        model(lite, "gemini", fail("network")).fake,
        model(oss, "groq", fail("refused")).fake,
      ],
    }),
    request,
    accept,
  );
  assert(!failed.ok);
  assertEquals(failed.code, "llm_failed");
  assertEquals(failed.calls[0].inputTokens, null, "no usage without an answer");
});

Deno.test("with nothing to ask, the answer is llm_unavailable", async () => {
  const result = await runChain(
    deps({ models: [model(lite, "gemini", good).fake], consent: false }),
    request,
    accept,
  );
  assert(!result.ok);
  assertEquals(result.code, "llm_unavailable");

  const unknown = await runChain(
    deps({ models: [model("not-configured", "groq", good).fake] }),
    request,
    accept,
  );
  assert(!unknown.ok);
  assertEquals(unknown.code, "llm_unavailable");
});
