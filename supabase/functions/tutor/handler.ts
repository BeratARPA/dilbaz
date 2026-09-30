/**
 * `tutor` function: one deployment, one route per path segment
 * (`/tutor/<route>`, docs/07-ai-tutor.md §4, docs/12 §7).
 *
 * Dependencies are injected so that routing, auth, the provider chain and
 * logging are tested without network access.
 */
import type { UserVerifier } from "../_shared/auth.ts";
import { json, jsonError, preflight } from "../_shared/http.ts";
import { logEvent, type LogSink } from "../_shared/log.ts";
import { llmConfig } from "../_shared/llm_config.ts";
import { type ModelUse, quotaDayStart } from "../_shared/llm/quota.ts";
import {
  type CallRecord,
  type ChainFailure,
  Cooldown,
  runChain,
} from "../_shared/llm/router.ts";
import type { LlmModel } from "../_shared/llm/types.ts";
import { answerCheckUserMessage } from "../_shared/prompts/answer_check.ts";
import { AnswerCheckInput } from "../_shared/schemas/answer_check.ts";
import { guard, kitFor, parseWire } from "./answer_check.ts";

export const version = "0.2.0";

/** What the learner allows and has used today, read with the service role. */
export interface LearnerState {
  /** `ai_data_consent` (ADR-0009). */
  consent: boolean;
  use: Map<string, ModelUse>;
}

export interface LlmDeps {
  /** Models whose provider key is set, by id. */
  models: ReadonlyMap<string, LlmModel>;
  /** Consent and each model's use since its quota day began. */
  learnerState(
    userId: string,
    models: { id: string; since: Date }[],
  ): Promise<LearnerState>;
  /** Writes the calls to `llm_usage`. */
  recordUsage(
    userId: string,
    route: string,
    calls: CallRecord[],
  ): Promise<void>;
}

export interface TutorDeps {
  verifyUser: UserVerifier;
  llm: LlmDeps;
  logSink?: LogSink;
  /** Monotonic milliseconds, for durations and cooldowns. */
  now?: () => number;
  /** Wall clock, for quota days. */
  clock?: () => Date;
}

/** Status of each way the chain can fail; the code tells the client why. */
const failureStatus: Record<ChainFailure, number> = {
  quota_exhausted: 429,
  llm_refused: 502,
  llm_failed: 502,
  llm_unavailable: 503,
};

const routeMethods: Record<string, string[]> = {
  health: ["GET", "POST"],
  answer_check: ["POST"],
};

/** Route name after the `tutor` segment, or null when absent. */
export function routeOf(url: string): string | null {
  const segments = new URL(url).pathname.split("/").filter(Boolean);
  const index = segments.indexOf("tutor");
  return index >= 0 && index + 1 < segments.length ? segments[index + 1] : null;
}

export function createTutorHandler(deps: TutorDeps) {
  const now = deps.now ?? (() => performance.now());
  const clock = deps.clock ?? (() => new Date());
  const cooldown = new Cooldown();

  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return preflight();

    const started = now();
    const requestId = crypto.randomUUID();
    const name = routeOf(request.url);

    const finish = (
      response: Response,
      code?: string,
      userId?: string,
      model?: string,
    ): Response => {
      logEvent(
        response.status >= 500 ? "error" : "info",
        "request",
        {
          fn: "tutor",
          requestId,
          route: name ?? undefined,
          userId,
          status: response.status,
          code,
          model,
          durationMs: Math.round(now() - started),
        },
        deps.logSink,
      );
      return response;
    };

    if (name === null || !Object.hasOwn(routeMethods, name)) {
      return finish(jsonError(404, "unknown_route"), "unknown_route");
    }
    if (!routeMethods[name].includes(request.method)) {
      return finish(jsonError(405, "method_not_allowed"), "method_not_allowed");
    }

    const auth = await deps.verifyUser(request);
    if (!auth.ok) return finish(jsonError(auth.status, auth.code), auth.code);
    const userId = auth.userId;
    const fail = (status: number, code: string) =>
      finish(jsonError(status, code), code, userId);

    if (name === "health") {
      return finish(json({ status: "ok", version }), undefined, userId);
    }

    // answer_check
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return fail(400, "bad_json");
    }
    const parsed = AnswerCheckInput.safeParse(body);
    if (!parsed.success) return fail(400, "invalid_input");
    const input = parsed.data;
    // No answer, no call (I-01, I-11).
    if (input.response.text.trim() === "") return fail(400, "missing_response");
    const kit = kitFor(`${input.ctx.l1}-${input.ctx.l2}`);
    if (!kit) return fail(400, "unsupported_pair");

    const route = llmConfig.routes.answer_check;
    const models = route.chain
      .map((id) => deps.llm.models.get(id))
      .filter((model): model is LlmModel => model !== undefined);
    if (models.length === 0) return fail(503, "llm_unavailable");

    const today = clock();
    let state: LearnerState;
    try {
      state = await deps.llm.learnerState(
        userId,
        models.map((model) => ({
          id: model.id,
          since: quotaDayStart(
            llmConfig.providers[model.provider].quotaDay,
            today,
          ),
        })),
      );
    } catch {
      // Without the learner's state: no consent-bound provider, no share.
      logEvent("warn", "state_unavailable", {
        fn: "tutor",
        requestId,
        route: name,
        userId,
      }, deps.logSink);
      state = { consent: false, use: new Map() };
    }

    const result = await runChain(
      { models, consent: state.consent, use: state.use, cooldown, now },
      {
        system: kit.system,
        user: answerCheckUserMessage(input),
        schemaName: "answer_check",
        schema: kit.schema,
        effort: route.effort,
        maxTokens: route.maxTokens,
        timeoutMs: route.timeoutMs,
      },
      (text) => parseWire(kit, text),
    );

    for (const call of result.calls) {
      logEvent("info", "llm_call", {
        fn: "tutor",
        requestId,
        route: name,
        userId,
        model: call.model,
        stopReason: call.stopReason,
        inputTokens: call.inputTokens ?? undefined,
        outputTokens: call.outputTokens ?? undefined,
        cacheReadTokens: call.cachedTokens ?? undefined,
        durationMs: call.latencyMs,
      }, deps.logSink);
    }
    if (result.calls.length > 0) {
      try {
        await deps.llm.recordUsage(userId, name, result.calls);
      } catch {
        logEvent("warn", "usage_not_recorded", {
          fn: "tutor",
          requestId,
          route: name,
          userId,
        }, deps.logSink);
      }
    }
    if (!result.ok) return fail(failureStatus[result.code], result.code);

    const { output, leaked } = guard(input, result.value, kit, {
      provider: result.model.provider,
      model: result.model.id,
    });
    if (leaked.length > 0) {
      logEvent("warn", "ladder_leak", {
        fn: "tutor",
        requestId,
        route: name,
        userId,
        model: result.model.id,
        code: leaked.join("."),
      }, deps.logSink);
    }
    return finish(json(output), undefined, userId, result.model.id);
  };
}
