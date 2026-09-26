/**
 * LLM cost and the per-user daily budget (docs/07-ai-tutor.md §3).
 *
 * When the budget is spent, routes answer `budget_exceeded` and the client
 * continues with deterministic checks (docs/07 §7).
 */
import { llmConfig, type ModelPricing } from "./llm_config.ts";

export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWrite5mTokens: number;
  cacheWrite1hTokens: number;
}

/** Pricing of [model]; unknown models use the default model's price. */
export function pricingFor(model: string): ModelPricing {
  return llmConfig.pricing[model] ?? llmConfig.pricing[llmConfig.model];
}

/** Cost in USD, as stored in `llm_usage.cost_usd` (6 decimals). */
export function costUsd(model: string, usage: TokenUsage): number {
  const p = pricingFor(model);
  const micro = usage.inputTokens * p.input +
    usage.outputTokens * p.output +
    usage.cacheReadTokens * p.cacheRead +
    usage.cacheWrite5mTokens * p.cacheWrite5m +
    usage.cacheWrite1hTokens * p.cacheWrite1h;
  return Math.round(micro) / 1_000_000;
}

/** Start of the UTC day containing [now]; budgets reset at 00:00 UTC. */
export function utcDayStart(now: Date): Date {
  return new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
}

export interface BudgetDecision {
  allowed: boolean;
  remainingUsd: number;
}

export function budgetDecision(
  spentTodayUsd: number,
  limitUsd: number = llmConfig.dailyBudgetUsd,
): BudgetDecision {
  const remainingUsd = Math.max(0, limitUsd - spentTodayUsd);
  return { allowed: spentTodayUsd < limitUsd, remainingUsd };
}
