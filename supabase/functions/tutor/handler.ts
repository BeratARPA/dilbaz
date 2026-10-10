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
import { llmConfig, type TutorRoute } from "../_shared/llm_config.ts";
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
import { speakingAnnotateUserMessage } from "../_shared/prompts/speaking_annotate.ts";
import { GapSuggestInput } from "../_shared/schemas/gap_suggest.ts";
import { SpeakingAnnotateInput } from "../_shared/schemas/speaking_annotate.ts";
import { guard, kitFor, parseWire } from "./answer_check.ts";
import { gapKitFor, parseGapWire, suggestGap } from "./gap_suggest.ts";
import {
  annotateKitFor,
  annotationOutput,
  parseAnnotateWire,
} from "./speaking_annotate.ts";

export const version = "0.4.0";

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
  gap_suggest: ["POST"],
  speaking_annotate: ["POST"],
};

/** Route name after the `tutor` segment, or null when absent. */
export function routeOf(url: string): string | null {
  const segments = new URL(url).pathname.split("/").filter(Boolean);
  const index = segments.indexOf("tutor");
  return index >= 0 && index + 1 < segments.length ? segments[index + 1] : null;
}

/** [use] after [calls]: the learner's share counts them at once. */
function counted(
  use: Map<string, ModelUse>,
  calls: CallRecord[],
): Map<string, ModelUse> {
  const next = new Map(use);
  for (const call of calls) {
    const before = next.get(call.model) ?? { requests: 0, tokens: 0 };
    next.set(call.model, {
      requests: before.requests + 1,
      tokens: before.tokens + (call.inputTokens ?? 0) -
        (call.cachedTokens ?? 0) + (call.outputTokens ?? 0),
    });
  }
  return next;
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

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return fail(400, "bad_json");
    }

    /** The route's chain: the models whose key is set, in order. */
    const chainOf = (route: TutorRoute) =>
      llmConfig.routes[route].chain
        .map((id) => deps.llm.models.get(id))
        .filter((model): model is LlmModel => model !== undefined);

    /** Consent and today's use of [models]. */
    const stateFor = async (models: LlmModel[]): Promise<LearnerState> => {
      const today = clock();
      try {
        return await deps.llm.learnerState(
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
        return { consent: false, use: new Map() };
      }
    };

    /** Logs the calls and writes them to `llm_usage`. */
    const record = async (calls: CallRecord[]) => {
      for (const call of calls) {
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
      if (calls.length === 0) return;
      try {
        await deps.llm.recordUsage(userId, name, calls);
      } catch {
        logEvent("warn", "usage_not_recorded", {
          fn: "tutor",
          requestId,
          route: name,
          userId,
        }, deps.logSink);
      }
    };

    if (name === "answer_check") {
      const parsed = AnswerCheckInput.safeParse(body);
      if (!parsed.success) return fail(400, "invalid_input");
      const input = parsed.data;
      // No answer, no call (I-01, I-11).
      if (input.response.text.trim() === "") {
        return fail(400, "missing_response");
      }
      const kit = kitFor(`${input.ctx.l1}-${input.ctx.l2}`);
      if (!kit) return fail(400, "unsupported_pair");

      const route = llmConfig.routes.answer_check;
      const models = chainOf("answer_check");
      if (models.length === 0) return fail(503, "llm_unavailable");
      const state = await stateFor(models);
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
      await record(result.calls);
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
    }

    if (name === "speaking_annotate") {
      const parsed = SpeakingAnnotateInput.safeParse(body);
      if (!parsed.success) return fail(400, "invalid_input");
      const input = parsed.data;
      // Nothing said, no call (I-01, I-11).
      if (input.words.length === 0) return fail(400, "missing_response");
      if (!input.words.every((word, i) => word.i === i)) {
        return fail(400, "invalid_input");
      }
      const kit = annotateKitFor(`${input.ctx.l1}-${input.ctx.l2}`);
      if (!kit) return fail(400, "unsupported_pair");

      const route = llmConfig.routes.speaking_annotate;
      const models = chainOf("speaking_annotate");
      if (models.length === 0) return fail(503, "llm_unavailable");
      const state = await stateFor(models);
      const result = await runChain(
        { models, consent: state.consent, use: state.use, cooldown, now },
        {
          system: kit.system,
          user: speakingAnnotateUserMessage(input),
          schemaName: "speaking_annotate",
          schema: kit.schema,
          effort: input.assessment ? llmConfig.assessmentEffort : route.effort,
          maxTokens: route.maxTokens,
          timeoutMs: route.timeoutMs,
        },
        (text) => parseAnnotateWire(kit, text),
      );
      await record(result.calls);
      if (!result.ok) return fail(failureStatus[result.code], result.code);

      const { output, leaked } = annotationOutput(input, result.value, kit, {
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
          code: leaked.join(","),
        }, deps.logSink);
      }
      return finish(json(output), undefined, userId, result.model.id);
    }

    // gap_suggest
    const parsed = GapSuggestInput.safeParse(body);
    if (!parsed.success) return fail(400, "invalid_input");
    const input = parsed.data;
    // Nothing to say, no call (I-11).
    if (input.l1_text.trim() === "") return fail(400, "missing_text");
    const kit = gapKitFor(input.ctx.l2);
    if (!kit) return fail(400, "unsupported_pair");

    const route = llmConfig.routes.gap_suggest;
    const models = chainOf("gap_suggest");
    if (models.length === 0) return fail(503, "llm_unavailable");
    const state = await stateFor(models);
    const result = await suggestGap(input, kit, (user, earlier) =>
      runChain(
        {
          models,
          consent: state.consent,
          // A second call sees the first in the learner's share.
          use: counted(state.use, earlier),
          cooldown,
          now,
        },
        {
          system: kit.system,
          user,
          schemaName: "gap_suggest",
          schema: kit.schema,
          effort: route.effort,
          maxTokens: route.maxTokens,
          timeoutMs: route.timeoutMs,
        },
        parseGapWire,
      ));
    await record(result.calls);
    if (!result.ok) return fail(failureStatus[result.code], result.code);
    return finish(json(result.output), undefined, userId, result.model.id);
  };
}
