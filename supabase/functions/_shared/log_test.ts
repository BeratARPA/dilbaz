import { assert, assertEquals } from "@std/assert";
import { logEvent, sanitize } from "./log.ts";

Deno.test("log lines are single-line JSON with level and event", () => {
  const lines: string[] = [];
  logEvent("warn", "llm_call", {
    fn: "tutor",
    requestId: "r-1",
    route: "answer_check",
    stopReason: "max_tokens",
    inputTokens: 120,
  }, (line) => lines.push(line));
  assertEquals(lines.length, 1);
  assert(!lines[0].includes("\n"));
  const entry = JSON.parse(lines[0]);
  assertEquals(entry.level, "warn");
  assertEquals(entry.event, "llm_call");
  assertEquals(entry.stopReason, "max_tokens");
  assertEquals(entry.inputTokens, 120);
  assert(!Number.isNaN(Date.parse(entry.ts)));
});

Deno.test("text in code-like fields is redacted", () => {
  const clean = sanitize({
    fn: "tutor",
    requestId: "r-1",
    code: "I have problem with my key",
    route: "answer_check",
  });
  assertEquals(clean.code, "redacted");
  assertEquals(clean.route, "answer_check");
});

Deno.test("non-identifier event names are redacted", () => {
  const lines: string[] = [];
  logEvent(
    "info",
    "user said hello",
    { fn: "tutor", requestId: "r" },
    (l) => lines.push(l),
  );
  assertEquals(JSON.parse(lines[0]).event, "redacted");
});
