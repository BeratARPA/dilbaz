import { assert, assertEquals } from "@std/assert";
import type { AuthOutcome, UserVerifier } from "../_shared/auth.ts";
import type { CallRecord } from "../_shared/llm/router.ts";
import type { LlmModel, LlmOutcome, LlmRequest } from "../_shared/llm/types.ts";
import {
  createTutorHandler,
  type LearnerState,
  type LlmDeps,
  routeOf,
  version,
} from "./handler.ts";

const userId = "0192f5a0-0000-7000-8000-000000000001";
const signedIn: UserVerifier = () =>
  Promise.resolve<AuthOutcome>({ ok: true, userId });
const signedOut: UserVerifier = () =>
  Promise.resolve<AuthOutcome>({
    ok: false,
    status: 401,
    code: "MISSING_CREDENTIALS",
  });

const lite = "gemini-3.1-flash-lite";
const oss = "openai/gpt-oss-120b";

const judged = {
  verdict: "minor_error",
  target_ok: false,
  error_tags: ["agr.3sg_s"],
  error_spans: [{ text: "work", tag: "agr.3sg_s" }],
  ladder: {
    h1: "Fiilin biçiminde küçük bir sorun var.",
    h2: "'work' kelimesine bak.",
    h3: "Geniş zamanda he, she ve it ile fiile -s eklenir.",
    h4: "He works every day.",
  },
  variant_to_learn: "",
  confidence: 0.93,
};

function fakeModel(
  id: string,
  provider: "gemini" | "groq",
  outcome: () => LlmOutcome,
) {
  const asked: LlmRequest[] = [];
  const model: LlmModel = {
    id,
    provider,
    generate(request) {
      asked.push(request);
      return Promise.resolve(outcome());
    },
  };
  return { model, asked };
}

const answer = (body: unknown): LlmOutcome => ({
  ok: true,
  text: JSON.stringify(body),
  usage: { inputTokens: 3900, outputTokens: 240, cachedTokens: 3500 },
  stopReason: "stop",
});

function setup(options: {
  verifyUser?: UserVerifier;
  models?: LlmModel[];
  state?: LearnerState | "fails";
  recordFails?: boolean;
} = {}) {
  const lines: string[] = [];
  const recorded: { userId: string; route: string; calls: CallRecord[] }[] = [];
  const asked: { id: string; since: Date }[][] = [];
  const llm: LlmDeps = {
    models: new Map((options.models ?? []).map((m) => [m.id, m])),
    learnerState(_, models) {
      asked.push(models);
      const state = options.state ??
        { consent: true, use: new Map() };
      return state === "fails"
        ? Promise.reject(new Error("db"))
        : Promise.resolve(state);
    },
    recordUsage(user, route, calls) {
      if (options.recordFails) return Promise.reject(new Error("db"));
      recorded.push({ userId: user, route, calls });
      return Promise.resolve();
    },
  };
  const handle = createTutorHandler({
    verifyUser: options.verifyUser ?? signedIn,
    llm,
    logSink: (line) => lines.push(line),
    clock: () => new Date("2026-09-30T10:00:00Z"),
  });
  return { handle, lines, recorded, asked };
}

const base = "http://localhost:54321/functions/v1/tutor";

const cardInput = {
  ctx: { l1: "tr", l2: "en", level: "A1", explain_in: "l1" },
  item: {
    key: "en.ws.work.v.1",
    prompt_l1: "O her gün çalışır.",
    reference_l2: "He works every day.",
    target_span: "works",
    grammar_codes: ["gp.present_simple.affirmative"],
  },
  response: { text: "he work every day", source: "asr", asr_confidence: 0.94 },
  attempt_no: 1,
};

const check = (body: unknown) =>
  new Request(`${base}/answer_check`, {
    method: "POST",
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

Deno.test("health answers ok with the version for a signed-in user", async () => {
  const { handle } = setup();
  const response = await handle(new Request(`${base}/health`));
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { status: "ok", version });
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("routes are reached only with a verified user", async () => {
  const { handle } = setup({ verifyUser: signedOut });
  const response = await handle(check(cardInput));
  assertEquals(response.status, 401);
  assertEquals(await response.json(), {
    error: { code: "MISSING_CREDENTIALS" },
  });
});

Deno.test("unknown routes are 404 without calling auth", async () => {
  let authCalls = 0;
  const { handle } = setup({
    verifyUser: () => {
      authCalls++;
      return signedIn(new Request(base));
    },
  });
  for (const path of ["nope", "constructor", "__proto__"]) {
    const response = await handle(new Request(`${base}/${path}`));
    assertEquals(response.status, 404, path);
    assertEquals(await response.json(), { error: { code: "unknown_route" } });
  }
  assertEquals(authCalls, 0);
});

Deno.test("wrong methods are 405", async () => {
  const { handle } = setup();
  for (
    const request of [
      new Request(`${base}/health`, { method: "DELETE" }),
      new Request(`${base}/answer_check`),
    ]
  ) {
    const response = await handle(request);
    assertEquals(response.status, 405);
    await response.body?.cancel();
  }
});

Deno.test("CORS preflight is answered without auth", async () => {
  const { handle } = setup({ verifyUser: signedOut });
  const response = await handle(
    new Request(`${base}/health`, { method: "OPTIONS" }),
  );
  assertEquals(response.status, 204);
  assert(
    response.headers.get("Access-Control-Allow-Headers")?.includes("apikey"),
  );
});

Deno.test("route names are read after the tutor segment", () => {
  assertEquals(routeOf(`${base}/health`), "health");
  assertEquals(routeOf("http://edge/tutor/answer_check?x=1"), "answer_check");
  assertEquals(routeOf("http://edge/tutor"), null);
  assertEquals(routeOf("http://edge/other/health"), null);
});

Deno.test("answer_check judges with the first model and records the call", async () => {
  const primary = fakeModel(lite, "gemini", () => answer(judged));
  const { handle, recorded, asked } = setup({ models: [primary.model] });

  const response = await handle(check(cardInput));

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.verdict, "minor_error");
  assertEquals(body.error_spans, [{ start: 3, end: 7, tag: "agr.3sg_s" }]);
  assertEquals(body.ladder.h4, "He works every day.");
  assertEquals(body.variant_to_learn, null);
  assertEquals(body.catalog, "tr-en@1");
  assertEquals(body.provider, "gemini");
  assertEquals(body.model, lite);

  // The fixed prompt and the learner's input go to the model.
  const [request] = primary.asked;
  assert(request.system.includes("# Error tags (tr-en@1)"));
  assertEquals(JSON.parse(request.user).response.text, "he work every day");
  assertEquals(request.maxTokens, 4000);

  // Use is counted from midnight Pacific time for Gemini.
  assertEquals(asked[0], [{
    id: lite,
    since: new Date("2026-09-30T07:00:00Z"),
  }]);
  assertEquals(recorded.length, 1);
  assertEquals(recorded[0].route, "answer_check");
  assertEquals(recorded[0].calls[0].inputTokens, 3900);
  assertEquals(recorded[0].calls[0].cachedTokens, 3500);
});

Deno.test("no answer, no call (I-01, I-11)", async () => {
  const primary = fakeModel(lite, "gemini", () => answer(judged));
  const { handle } = setup({ models: [primary.model] });

  for (
    const [body, code] of [
      ["{", "bad_json"],
      [{ ...cardInput, attempt_no: 4 }, "invalid_input"],
      [
        { ...cardInput, response: { text: "  ", source: "asr" } },
        "missing_response",
      ],
      [
        { ...cardInput, ctx: { ...cardInput.ctx, l2: "de" } },
        "unsupported_pair",
      ],
    ] as const
  ) {
    const response = await handle(check(body));
    assertEquals(response.status, 400, code);
    assertEquals(await response.json(), { error: { code } });
  }
  assertEquals(primary.asked.length, 0);
});

Deno.test("without a model key the route is unavailable", async () => {
  const { handle } = setup();
  const response = await handle(check(cardInput));
  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: { code: "llm_unavailable" } });
});

Deno.test("a spent share is 429, and the client checks without the LLM", async () => {
  const primary = fakeModel(lite, "gemini", () => answer(judged));
  const { handle, recorded } = setup({
    models: [primary.model],
    state: {
      consent: true,
      use: new Map([[lite, { requests: 250, tokens: 0 }]]),
    },
  });

  const response = await handle(check(cardInput));

  assertEquals(response.status, 429);
  assertEquals(await response.json(), { error: { code: "quota_exhausted" } });
  assertEquals(recorded, [], "nothing was called");
});

Deno.test("when the learner's state cannot be read, Gemini is not asked", async () => {
  const primary = fakeModel(lite, "gemini", () => answer(judged));
  const fallback = fakeModel(oss, "groq", () => answer(judged));
  const { handle, lines } = setup({
    models: [primary.model, fallback.model],
    state: "fails",
  });

  const response = await handle(check(cardInput));

  assertEquals(response.status, 200);
  assertEquals((await response.json()).provider, "groq");
  assertEquals(primary.asked.length, 0);
  assert(lines.some((line) => JSON.parse(line).event === "state_unavailable"));
});

Deno.test("a failed usage write does not cost the learner the answer", async () => {
  const primary = fakeModel(lite, "gemini", () => answer(judged));
  const { handle, lines } = setup({
    models: [primary.model],
    recordFails: true,
  });

  const response = await handle(check(cardInput));

  assertEquals(response.status, 200);
  await response.body?.cancel();
  assert(lines.some((line) => JSON.parse(line).event === "usage_not_recorded"));
});

Deno.test("logs carry codes and counts, never the learner's text", async () => {
  const leaky = {
    ...judged,
    ladder: { ...judged.ladder, h2: "Doğrusu 'works' olur." },
  };
  const primary = fakeModel(lite, "gemini", () => answer(leaky));
  const { handle, lines } = setup({ models: [primary.model] });

  const response = await handle(check(cardInput));
  const body = await response.json();

  assertEquals(body.ladder.h2, "", "the leaking hint is blanked");
  const events = lines.map((line) => JSON.parse(line));
  assertEquals(events.map((e) => e.event), [
    "llm_call",
    "ladder_leak",
    "request",
  ]);
  assertEquals(events[0].model, lite);
  assertEquals(events[0].inputTokens, 3900);
  assertEquals(events[1].code, "h2");
  assertEquals(events[2].status, 200);
  for (const line of lines) {
    assert(!line.includes("work every day"), "no answer text in logs");
    assert(!line.includes("çalışır"), "no prompt text in logs");
  }
});

Deno.test("when every model fails, the code says why", async () => {
  const refusing = fakeModel(lite, "gemini", () => ({
    ok: false,
    failure: "refused",
  }));
  const { handle, recorded } = setup({ models: [refusing.model] });

  const response = await handle(check(cardInput));

  assertEquals(response.status, 502);
  assertEquals(await response.json(), { error: { code: "llm_refused" } });
  assertEquals(recorded[0].calls[0].stopReason, "refused");
});

const flash = "gemini-3.5-flash";

const gapInput = {
  ctx: { l1: "tr", l2: "en", level: "A1", explain_in: "l1" },
  l1_text: "Toplantıyı yarına erteleyebilir miyiz?",
  context: "daily",
};

const suggestion = (simple: string) => ({
  l2_natural: "Could we postpone the meeting until tomorrow?",
  l2_simple: simple,
  key_chunk: { text: "the meeting", gloss_l1: "toplantı" },
  register: "neutral",
  notes_l1: "",
});

const suggest = (body: unknown) =>
  new Request(`${base}/gap_suggest`, {
    method: "POST",
    body: JSON.stringify(body),
  });

Deno.test("gap_suggest answers with the first model at the level", async () => {
  const primary = fakeModel(
    flash,
    "gemini",
    () => answer(suggestion("Can we have the meeting tomorrow?")),
  );
  const { handle, recorded } = setup({ models: [primary.model] });

  const response = await handle(suggest(gapInput));

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    l2_natural: "Could we postpone the meeting until tomorrow?",
    l2_simple: "Can we have the meeting tomorrow?",
    key_chunk: { text: "the meeting", gloss_l1: "toplantı" },
    register: "neutral",
    notes_l1: null,
    above_level: [],
    simplified: false,
    provider: "gemini",
    model: flash,
  });
  const [request] = primary.asked;
  assertEquals(request.schemaName, "gap_suggest");
  assertEquals(JSON.parse(request.user).l1_text, gapInput.l1_text);
  assertEquals(recorded[0].route, "gap_suggest");
});

Deno.test("too hard for the level: one simplify call, counted in the share", async () => {
  const answers = [
    suggestion("Could we postpone the conference indefinitely?"),
    suggestion("Can we have the meeting tomorrow?"),
  ];
  const primary = fakeModel(flash, "gemini", () => answer(answers.shift()));
  const { handle, recorded } = setup({ models: [primary.model] });

  const response = await handle(suggest(gapInput));
  const body = await response.json();

  assertEquals(body.l2_simple, "Can we have the meeting tomorrow?");
  assertEquals(body.simplified, true);
  assertEquals(primary.asked.length, 2);
  const retry = JSON.parse(primary.asked[1].user);
  assertEquals(
    retry.simplify.previous,
    "Could we postpone the conference indefinitely?",
  );
  assert(retry.simplify.above_level.includes("postpone"));
  assertEquals(recorded[0].calls.length, 2, "both calls are recorded");
});

Deno.test("a failed simplify call keeps the first answer and its hard words", async () => {
  let calls = 0;
  const primary = fakeModel(
    flash,
    "gemini",
    () =>
      calls++ === 0
        ? answer(suggestion("Could we postpone the conference indefinitely?"))
        : { ok: false, failure: "server" },
  );
  const { handle } = setup({ models: [primary.model] });

  const body = await (await handle(suggest(gapInput))).json();

  assertEquals(body.simplified, false);
  assertEquals(
    body.l2_simple,
    "Could we postpone the conference indefinitely?",
  );
  assert(body.above_level.includes("postpone"));
});

Deno.test("the second call stays within the learner's share", async () => {
  const primary = fakeModel(
    flash,
    "gemini",
    () => answer(suggestion("Could we postpone the conference indefinitely?")),
  );
  const { handle } = setup({
    models: [primary.model],
    // One request left of the learner's half of 20.
    state: {
      consent: true,
      use: new Map([[flash, { requests: 9, tokens: 0 }]]),
    },
  });

  const body = await (await handle(suggest(gapInput))).json();

  assertEquals(primary.asked.length, 1, "no request past the share");
  assertEquals(body.simplified, false);
});

Deno.test("gap_suggest needs something to say and a known language", async () => {
  const primary = fakeModel(flash, "gemini", () => answer(suggestion("x")));
  const { handle } = setup({ models: [primary.model] });

  for (
    const [body, code] of [
      [{ ...gapInput, context: "work" }, "invalid_input"],
      [{ ...gapInput, l1_text: "   " }, "missing_text"],
      [{ ...gapInput, ctx: { ...gapInput.ctx, l2: "de" } }, "unsupported_pair"],
    ] as const
  ) {
    const response = await handle(suggest(body));
    assertEquals(response.status, 400, code);
    assertEquals(await response.json(), { error: { code } });
  }
  assertEquals(primary.asked.length, 0);
});

Deno.test("gap_suggest without a consent goes to Groq; without models it waits", async () => {
  const gemini = fakeModel(flash, "gemini", () => answer(suggestion("x")));
  const groq = fakeModel(
    oss,
    "groq",
    () => answer(suggestion("Can we meet tomorrow?")),
  );
  const { handle } = setup({
    models: [gemini.model, groq.model],
    state: { consent: false, use: new Map() },
  });
  const body = await (await handle(suggest(gapInput))).json();
  assertEquals(body.provider, "groq");
  assertEquals(gemini.asked.length, 0);

  const none = setup();
  const response = await none.handle(suggest(gapInput));
  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: { code: "llm_unavailable" } });
});

Deno.test("gap_suggest logs never carry the learner's text", async () => {
  const primary = fakeModel(
    flash,
    "gemini",
    () => answer(suggestion("Can we have the meeting tomorrow?")),
  );
  const { handle, lines } = setup({ models: [primary.model] });
  const response = await handle(suggest(gapInput));
  await response.body?.cancel();
  for (const line of lines) {
    assert(!line.includes("Toplantı"), "no Turkish text in logs");
    assert(!line.includes("meeting"), "no English text in logs");
  }
});

const spoken = "my home big uh i like it".split(" ");
const speakingInput = {
  ctx: { l1: "tr", l2: "en", level: "A1", explain_in: "l1" },
  task: { prompt_l1: "Evini anlat.", goal: "Describe your home." },
  words: spoken.map((w, i) => ({
    i,
    w,
    start_ms: i * 400,
    end_ms: i * 400 + 300,
  })),
};

const annotation = {
  clauses: [
    { start_i: 0, end_i: 2, as_unit: 0, error_free: true },
    { start_i: 3, end_i: 6, as_unit: 1, error_free: true },
  ],
  errors: [
    {
      start_i: 1,
      end_i: 1,
      tag: "be.missing",
      correction: "home is",
      severity: 2,
    },
  ],
  fillers: [{ i: 3, kind: "l2" }],
  repairs: [],
  structures_used: [],
  task_outcome: "partial",
  strengths: ["'I like it' doğru."],
  corrections: [{
    original: "my home big",
    corrected: "My home is big.",
    meaning_l1: "Evim büyük.",
    tag: "be.missing",
    severity: 2,
    ladder: {
      h1: "Bir kelime eksik.",
      h2: "'home' ile 'big' arasına bak.",
      h3: "Şöyle de: My home is big.",
    },
  }],
};

const annotate = (body: unknown) =>
  new Request(`${base}/speaking_annotate`, {
    method: "POST",
    body: JSON.stringify(body),
  });

Deno.test("speaking_annotate marks the transcript with the first model", async () => {
  const primary = fakeModel(flash, "gemini", () => answer(annotation));
  const { handle, recorded, lines } = setup({ models: [primary.model] });

  const response = await handle(annotate(speakingInput));

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.clauses[0].error_free, false);
  assertEquals(body.task_outcome, "partial");
  // The hint that gave the sentence away is blank for the client's template.
  assertEquals(body.corrections[0].ladder.h3, "");
  assertEquals(body.catalog, "tr-en@1");
  assertEquals(body.prompt_version, "speaking_annotate@1");
  assertEquals(body.model, flash);
  const request = primary.asked[0];
  assertEquals(request.schemaName, "speaking_annotate");
  assertEquals(request.effort, "medium");
  assertEquals(request.maxTokens, 12000);
  assert(request.user.includes("[0]my [1]home"));
  assertEquals(recorded[0].route, "speaking_annotate");
  assert(lines.some((line) => line.includes("ladder_leak")));
  for (const line of lines) {
    assert(!line.includes("home"), "no transcript in logs");
  }
});

Deno.test("the monthly test's annotation thinks deeper", async () => {
  const primary = fakeModel(flash, "gemini", () => answer(annotation));
  const { handle } = setup({ models: [primary.model] });
  const response = await handle(
    annotate({ ...speakingInput, assessment: true }),
  );
  await response.body?.cancel();
  assertEquals(primary.asked[0].effort, "high");
});

Deno.test("speaking_annotate needs words in order and a known pair", async () => {
  const primary = fakeModel(flash, "gemini", () => answer(annotation));
  const { handle } = setup({ models: [primary.model] });
  const swapped = [...speakingInput.words];
  [swapped[0], swapped[1]] = [swapped[1], swapped[0]];
  for (
    const [body, code] of [
      [{ ...speakingInput, words: [] }, "missing_response"],
      [{ ...speakingInput, words: swapped }, "invalid_input"],
      [{ ...speakingInput, task: { goal: "x" } }, "invalid_input"],
      [
        { ...speakingInput, ctx: { ...speakingInput.ctx, l2: "de" } },
        "unsupported_pair",
      ],
    ] as const
  ) {
    const response = await handle(annotate(body));
    assertEquals(response.status, 400, code);
    assertEquals(await response.json(), { error: { code } });
  }
  assertEquals(primary.asked.length, 0);
});

Deno.test("speaking_annotate asks no one without consent: the marks wait", async () => {
  const primary = fakeModel(flash, "gemini", () => answer(annotation));
  const { handle } = setup({
    models: [primary.model],
    state: { consent: false, use: new Map() },
  });
  const response = await handle(annotate(speakingInput));
  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: { code: "llm_unavailable" } });
  assertEquals(primary.asked.length, 0);
});
