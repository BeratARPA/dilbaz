import { assert, assertEquals } from "@std/assert";
import { quotaDayEnd, quotaDayStart, withinShare } from "./quota.ts";

const la = "America/Los_Angeles";

Deno.test("Gemini's quota day starts at midnight Pacific time", () => {
  // 10:00 UTC on 30 September is 03:00 PDT (UTC-7).
  assertEquals(
    quotaDayStart(la, new Date("2026-09-30T10:00:00Z")).toISOString(),
    "2026-09-30T07:00:00.000Z",
  );
  // 05:00 UTC is still 29 September in Los Angeles.
  assertEquals(
    quotaDayStart(la, new Date("2026-09-30T05:00:00Z")).toISOString(),
    "2026-09-29T07:00:00.000Z",
  );
  assertEquals(
    quotaDayEnd(la, new Date("2026-09-30T10:00:00Z")).toISOString(),
    "2026-10-01T07:00:00.000Z",
  );
});

Deno.test("the day that ends summer time is 25 hours long", () => {
  // 1 November 2026: PDT (UTC-7) until 02:00, then PST (UTC-8).
  const noon = new Date("2026-11-01T20:00:00Z");
  assertEquals(
    quotaDayStart(la, noon).toISOString(),
    "2026-11-01T07:00:00.000Z",
  );
  assertEquals(quotaDayEnd(la, noon).toISOString(), "2026-11-02T08:00:00.000Z");
});

Deno.test("a UTC quota day is the calendar day", () => {
  assertEquals(
    quotaDayStart("UTC", new Date("2026-09-30T23:59:59Z")).toISOString(),
    "2026-09-30T00:00:00.000Z",
  );
  assertEquals(
    quotaDayEnd("UTC", new Date("2026-09-30T00:00:00Z")).toISOString(),
    "2026-10-01T00:00:00.000Z",
  );
});

Deno.test("each learner gets half of every quota", () => {
  const lite = { provider: "gemini" as const, requestsPerDay: 500 };
  assert(withinShare(lite, { requests: 249, tokens: 0 }));
  assert(!withinShare(lite, { requests: 250, tokens: 0 }));

  const oss = {
    provider: "groq" as const,
    requestsPerDay: 1000,
    tokensPerDay: 200_000,
  };
  assert(withinShare(oss, { requests: 10, tokens: 99_999 }));
  assert(!withinShare(oss, { requests: 10, tokens: 100_000 }), "tokens too");
});
