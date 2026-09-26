/**
 * `tutor` function: one deployment, one route per path segment
 * (`/tutor/<route>`, docs/07-ai-tutor.md §4, docs/12 §7).
 *
 * Dependencies are injected so that routing, auth and logging are tested
 * without network access.
 */
import type { UserVerifier } from "../_shared/auth.ts";
import { json, jsonError, preflight } from "../_shared/http.ts";
import { logEvent, type LogSink } from "../_shared/log.ts";

export const version = "0.1.0";

export interface TutorDeps {
  verifyUser: UserVerifier;
  logSink?: LogSink;
  now?: () => number;
}

interface RouteContext {
  userId: string;
}

type RouteHandler = (request: Request, ctx: RouteContext) => Promise<Response>;

const routes: Record<string, { methods: string[]; handle: RouteHandler }> = {
  health: {
    methods: ["GET", "POST"],
    handle: () => Promise.resolve(json({ status: "ok", version })),
  },
};

/** Route name after the `tutor` segment, or null when absent. */
export function routeOf(url: string): string | null {
  const segments = new URL(url).pathname.split("/").filter(Boolean);
  const index = segments.indexOf("tutor");
  return index >= 0 && index + 1 < segments.length ? segments[index + 1] : null;
}

export function createTutorHandler(deps: TutorDeps) {
  const now = deps.now ?? (() => performance.now());

  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return preflight();

    const started = now();
    const requestId = crypto.randomUUID();
    const name = routeOf(request.url);

    const finish = (
      response: Response,
      code?: string,
      userId?: string,
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
          durationMs: Math.round(now() - started),
        },
        deps.logSink,
      );
      return response;
    };

    const route = name === null ? undefined : routes[name];
    if (!route) return finish(jsonError(404, "unknown_route"), "unknown_route");
    if (!route.methods.includes(request.method)) {
      return finish(jsonError(405, "method_not_allowed"), "method_not_allowed");
    }

    const auth = await deps.verifyUser(request);
    if (!auth.ok) return finish(jsonError(auth.status, auth.code), auth.code);

    const response = await route.handle(request, { userId: auth.userId });
    return finish(response, undefined, auth.userId);
  };
}
