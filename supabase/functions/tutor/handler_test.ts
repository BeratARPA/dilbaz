import { assert, assertEquals } from "@std/assert";
import type { AuthOutcome, UserVerifier } from "../_shared/auth.ts";
import { createTutorHandler, routeOf, version } from "./handler.ts";

const userId = "0192f5a0-0000-7000-8000-000000000001";
const signedIn: UserVerifier = () =>
  Promise.resolve<AuthOutcome>({ ok: true, userId });
const signedOut: UserVerifier = () =>
  Promise.resolve<AuthOutcome>({
    ok: false,
    status: 401,
    code: "MISSING_CREDENTIALS",
  });

function setup(verifyUser: UserVerifier = signedIn) {
  const lines: string[] = [];
  const handle = createTutorHandler({
    verifyUser,
    logSink: (line) => lines.push(line),
  });
  return { handle, lines };
}

const base = "http://localhost:54321/functions/v1/tutor";

Deno.test("health answers ok with the version for a signed-in user", async () => {
  const { handle } = setup();
  const response = await handle(new Request(`${base}/health`));
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { status: "ok", version });
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("routes are reached only with a verified user", async () => {
  const { handle } = setup(signedOut);
  const response = await handle(new Request(`${base}/health`));
  assertEquals(response.status, 401);
  assertEquals(await response.json(), {
    error: { code: "MISSING_CREDENTIALS" },
  });
});

Deno.test("unknown routes are 404 without calling auth", async () => {
  let authCalls = 0;
  const { handle } = setup(() => {
    authCalls++;
    return signedIn(new Request(base));
  });
  const response = await handle(new Request(`${base}/nope`));
  assertEquals(response.status, 404);
  assertEquals(await response.json(), { error: { code: "unknown_route" } });
  assertEquals(authCalls, 0);
});

Deno.test("wrong methods are 405", async () => {
  const { handle } = setup();
  const response = await handle(
    new Request(`${base}/health`, { method: "DELETE" }),
  );
  assertEquals(response.status, 405);
  await response.body?.cancel();
});

Deno.test("CORS preflight is answered without auth", async () => {
  const { handle } = setup(signedOut);
  const response = await handle(
    new Request(`${base}/health`, { method: "OPTIONS" }),
  );
  assertEquals(response.status, 204);
  assert(
    response.headers.get("Access-Control-Allow-Headers")?.includes("apikey"),
  );
});

Deno.test("each request writes one structured log line without text", async () => {
  const { handle, lines } = setup();
  const response = await handle(
    new Request(`${base}/health`, {
      method: "POST",
      body: JSON.stringify({ text: "I have problem with my key" }),
    }),
  );
  await response.body?.cancel();
  assertEquals(lines.length, 1);
  const entry = JSON.parse(lines[0]);
  assertEquals(entry.fn, "tutor");
  assertEquals(entry.route, "health");
  assertEquals(entry.userId, userId);
  assertEquals(entry.status, 200);
  assert(typeof entry.durationMs === "number");
  assert(!lines[0].includes("problem"), "request text must not be logged");
});

Deno.test("route names are read after the tutor segment", () => {
  assertEquals(routeOf(`${base}/health`), "health");
  assertEquals(routeOf("http://edge/tutor/answer_check?x=1"), "answer_check");
  assertEquals(routeOf("http://edge/tutor"), null);
  assertEquals(routeOf("http://edge/other/health"), null);
});
