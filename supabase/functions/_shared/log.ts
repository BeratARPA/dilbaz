/**
 * Structured JSON logs (docs/12-architecture.md §7, docs/14 §1).
 *
 * Only identifiers, codes, counts and durations can be logged: the field set
 * is closed and code-like fields are checked at runtime, so a transcript or
 * any personal text can never reach the logs.
 */

export type LogLevel = "info" | "warn" | "error";

export interface LogFields {
  fn: string;
  requestId: string;
  route?: string;
  userId?: string;
  status?: number;
  code?: string;
  durationMs?: number;
  model?: string;
  stopReason?: string;
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
}

export type LogSink = (line: string) => void;

const codeLike = /^[A-Za-z0-9_.:@-]{1,64}$/;
const codeFields = [
  "fn",
  "requestId",
  "route",
  "userId",
  "code",
  "model",
  "stopReason",
] as const;

/** Replaces any code-like field that is not a short identifier. */
export function sanitize(fields: LogFields): LogFields {
  const clean: LogFields = { ...fields };
  for (const key of codeFields) {
    const value = clean[key];
    if (value !== undefined && !codeLike.test(value)) {
      clean[key] = "redacted";
    }
  }
  return clean;
}

export function logEvent(
  level: LogLevel,
  event: string,
  fields: LogFields,
  sink: LogSink = console.log,
): void {
  const safeEvent = codeLike.test(event) ? event : "redacted";
  sink(
    JSON.stringify({
      ts: new Date().toISOString(),
      level,
      event: safeEvent,
      ...sanitize(fields),
    }),
  );
}
