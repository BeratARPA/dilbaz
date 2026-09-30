/**
 * Free quotas and the fair share (docs/07-ai-tutor.md §3, ADR-0009).
 *
 * The two learners share every quota; each may use half of it. Daily
 * counters follow the provider's own day (Gemini: midnight Pacific time).
 */
import { llmConfig, type ModelConfig } from "../llm_config.ts";

/** What one learner used of a model since its quota day began. */
export interface ModelUse {
  requests: number;
  /** Uncached input plus output tokens. */
  tokens: number;
}

/** Milliseconds [zone]'s wall clock is ahead of UTC at [instant]. */
function zoneOffsetMs(zone: string, instant: Date): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: zone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(instant);
  const part = (type: string) =>
    Number(parts.find((p) => p.type === type)?.value);
  const wall = Date.UTC(
    part("year"),
    part("month") - 1,
    part("day"),
    part("hour"),
    part("minute"),
    part("second"),
  );
  return wall - Math.floor(instant.getTime() / 1000) * 1000;
}

/** The instant the quota day containing [now] began in [zone]. */
export function quotaDayStart(zone: string, now: Date): Date {
  const local = new Date(now.getTime() + zoneOffsetMs(zone, now));
  const midnight = Date.UTC(
    local.getUTCFullYear(),
    local.getUTCMonth(),
    local.getUTCDate(),
  );
  // The offset at midnight itself: a DST change may fall in between.
  const guess = new Date(midnight - zoneOffsetMs(zone, now));
  return new Date(midnight - zoneOffsetMs(zone, guess));
}

/** When the quota day containing [now] ends in [zone]. */
export function quotaDayEnd(zone: string, now: Date): Date {
  const start = quotaDayStart(zone, now);
  // 26 hours always lands in the next day, whatever the DST change.
  return quotaDayStart(zone, new Date(start.getTime() + 26 * 3_600_000));
}

/** Whether a learner who used [use] may call [model] again today. */
export function withinShare(
  model: ModelConfig,
  use: ModelUse,
  share: number = llmConfig.fairShare,
): boolean {
  if (use.requests >= Math.floor(model.requestsPerDay * share)) return false;
  const tokens = model.tokensPerDay;
  return tokens === undefined || use.tokens < Math.floor(tokens * share);
}
