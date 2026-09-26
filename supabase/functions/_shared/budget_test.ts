import { assertEquals } from "@std/assert";
import { budgetDecision, costUsd, pricingFor, utcDayStart } from "./budget.ts";
import { llmConfig } from "./llm_config.ts";

const none = {
  inputTokens: 0,
  outputTokens: 0,
  cacheReadTokens: 0,
  cacheWrite5mTokens: 0,
  cacheWrite1hTokens: 0,
};

Deno.test("cost uses per-million prices for every token kind", () => {
  // answer_check-sized call: 3000 cached prompt tokens, 400 new, 600 out.
  const usage = {
    ...none,
    inputTokens: 400,
    outputTokens: 600,
    cacheReadTokens: 3000,
  };
  // 400*5 + 600*25 + 3000*0.5 = 2000 + 15000 + 1500 = 18500 micro-USD
  assertEquals(costUsd("claude-opus-5", usage), 0.0185);
});

Deno.test("cache writes cost 1.25x (5 min) and 2x (1 h) of input", () => {
  assertEquals(
    costUsd("claude-opus-5", { ...none, cacheWrite5mTokens: 1_000_000 }),
    6.25,
  );
  assertEquals(
    costUsd("claude-opus-5", { ...none, cacheWrite1hTokens: 1_000_000 }),
    10,
  );
});

Deno.test("a fallback model is costed at its own price", () => {
  const usage = { ...none, inputTokens: 1_000_000, outputTokens: 1_000_000 };
  assertEquals(costUsd("claude-sonnet-5", usage), 12);
  assertEquals(costUsd("claude-opus-5", usage), 30);
});

Deno.test("unknown models are costed at the default model's price", () => {
  assertEquals(pricingFor("claude-unknown"), pricingFor(llmConfig.model));
});

Deno.test("cost is rounded to micro-dollars like llm_usage.cost_usd", () => {
  // 1 input token = 5e-6 USD; 1 cache-read token = 5e-7 USD -> rounds to 1e-6.
  assertEquals(
    costUsd("claude-opus-5", { ...none, cacheReadTokens: 1 }),
    0.000001,
  );
});

Deno.test("budget allows spending below the daily ceiling only", () => {
  assertEquals(budgetDecision(0), { allowed: true, remainingUsd: 1.5 });
  assertEquals(budgetDecision(1.4999).allowed, true);
  assertEquals(budgetDecision(1.5), { allowed: false, remainingUsd: 0 });
  assertEquals(budgetDecision(2), { allowed: false, remainingUsd: 0 });
});

Deno.test("budget days start at 00:00 UTC", () => {
  const lateEvening = new Date("2026-09-26T23:30:00+03:00"); // 20:30 UTC
  assertEquals(
    utcDayStart(lateEvening).toISOString(),
    "2026-09-26T00:00:00.000Z",
  );
  const afterMidnightUtc = new Date("2026-09-27T02:30:00+03:00"); // 23:30 UTC
  assertEquals(
    utcDayStart(afterMidnightUtc).toISOString(),
    "2026-09-26T00:00:00.000Z",
  );
});
