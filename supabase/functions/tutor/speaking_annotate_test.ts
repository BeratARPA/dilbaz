import { assert, assertEquals } from "@std/assert";
import type {
  SpeakingAnnotateInput,
  SpeakingAnnotateWire,
} from "../_shared/schemas/speaking_annotate.ts";
import {
  annotateKitFor,
  annotationOutput,
  maxCorrections,
  parseAnnotateWire,
} from "./speaking_annotate.ts";

const kit = annotateKitFor("tr-en")!;
const served = { provider: "gemini", model: "gemini-3.5-flash" };

const said = "my home big uh i like it";
const input: SpeakingAnnotateInput = {
  ctx: { l1: "tr", l2: "en", level: "A1", explain_in: "l1" },
  task: {
    prompt_l1: "Evini anlat.",
    goal: "Describe your home.",
    can_do_codes: [],
  },
  words: said.split(" ").map((w, i) => ({
    i,
    w,
    start_ms: i * 400,
    end_ms: i * 400 + 300,
  })),
  assessment: false,
};

const ladder = {
  h1: "Bir kelime eksik.",
  h2: "'home big' kısmına bak.",
  h3: "Be fiili gerekir.",
};

function wire(
  changes: Partial<SpeakingAnnotateWire> = {},
): SpeakingAnnotateWire {
  return {
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
    corrections: [
      {
        original: "my home big",
        corrected: "My home is big.",
        meaning_l1: "Evim büyük.",
        tag: "be.missing",
        severity: 2,
        ladder,
      },
    ],
    ...changes,
  };
}

Deno.test("a pair without a catalog has no kit", () => {
  assertEquals(annotateKitFor("tr-de"), null);
  assertEquals(annotateKitFor("tr-en"), kit);
});

Deno.test("only valid JSON with the closed lists is an answer", () => {
  assertEquals(parseAnnotateWire(kit, JSON.stringify(wire())), wire());
  assertEquals(parseAnnotateWire(kit, "{"), null);
  const unknownTag = wire({
    errors: [{
      start_i: 1,
      end_i: 1,
      tag: "x.y",
      correction: "is",
      severity: 1,
    }],
  });
  assertEquals(parseAnnotateWire(kit, JSON.stringify(unknownTag)), null);
  const pronunciation = wire({
    errors: [{
      start_i: 1,
      end_i: 1,
      tag: "phon.th",
      correction: "x",
      severity: 1,
    }],
  });
  assertEquals(parseAnnotateWire(kit, JSON.stringify(pronunciation)), null);
  const unknownCode = wire({
    structures_used: [{ code: "gp.nope", start_i: 0, end_i: 1, correct: true }],
  });
  assertEquals(parseAnnotateWire(kit, JSON.stringify(unknownCode)), null);
  const severity = wire({
    errors: [{
      start_i: 1,
      end_i: 1,
      tag: "be.missing",
      correction: "is",
      severity: 4,
    }],
  });
  assertEquals(parseAnnotateWire(kit, JSON.stringify(severity)), null);
});

Deno.test("error_free follows the marked errors", () => {
  const { output } = annotationOutput(input, wire(), kit, served);
  assertEquals(output.clauses.map((c) => c.error_free), [false, true]);
  assertEquals(output.catalog, "tr-en@1");
  assertEquals(output.prompt_version, "speaking_annotate@1");
  assertEquals(output.provider, "gemini");
  assertEquals(output.task_outcome, "partial");
});

Deno.test("marks outside the transcript, overlaps and repeats are dropped", () => {
  const { output } = annotationOutput(
    input,
    wire({
      clauses: [
        { start_i: 3, end_i: 6, as_unit: 1, error_free: true },
        { start_i: 0, end_i: 2, as_unit: 0, error_free: false },
        { start_i: 2, end_i: 4, as_unit: 1, error_free: true },
        { start_i: 5, end_i: 9, as_unit: 2, error_free: true },
      ],
      errors: [
        {
          start_i: 1,
          end_i: 1,
          tag: "be.missing",
          correction: "home is",
          severity: 2,
        },
        {
          start_i: 6,
          end_i: 7,
          tag: "art.missing",
          correction: "a",
          severity: 1,
        },
        {
          start_i: 4,
          end_i: 3,
          tag: "art.missing",
          correction: "a",
          severity: 1,
        },
      ],
      fillers: [{ i: 3, kind: "l2" }, { i: 3, kind: "l1" }, {
        i: 7,
        kind: "l2",
      }],
      repairs: [{ start_i: 0, end_i: 0 }, { start_i: 6, end_i: 8 }],
      structures_used: [
        { code: "gp.like_ing", start_i: 4, end_i: 6, correct: true },
        { code: "gp.like_ing", start_i: 4, end_i: 9, correct: true },
      ],
    }),
    kit,
    served,
  );
  assertEquals(output.clauses.map((c) => [c.start_i, c.end_i]), [[0, 2], [
    3,
    6,
  ]]);
  assertEquals(output.errors.length, 1);
  assertEquals(output.fillers, [{ i: 3, kind: "l2" }]);
  assertEquals(output.repairs, [{ start_i: 0, end_i: 0 }]);
  assertEquals(output.structures_used.length, 1);
});

Deno.test("at most two strengths and five corrections, none empty", () => {
  const correction = wire().corrections[0];
  const { output } = annotationOutput(
    input,
    wire({
      strengths: ["  ", "Bir.", "İki.", "Üç."],
      corrections: [
        { ...correction, corrected: correction.original },
        { ...correction, original: " " },
        ...Array.from({ length: 6 }, (_, i) => ({
          ...correction,
          original: `my home big ${i}`,
        })),
      ],
    }),
    kit,
    served,
  );
  assertEquals(output.strengths, ["Bir.", "İki."]);
  assertEquals(output.corrections.length, maxCorrections);
  assert(
    output.corrections.every((c) => c.original.startsWith("my home big ")),
  );
});

Deno.test("a hint that gives the correction away is blanked (I-02)", () => {
  const { output, leaked } = annotationOutput(
    input,
    wire({
      corrections: [
        {
          original: "my home big",
          corrected: "My home is big.",
          meaning_l1: "Evim büyük.",
          tag: "be.missing",
          severity: 2,
          ladder: {
            h1: "Bir kelime eksik.",
            h2: "'home' ile 'big' arasına is gelir.",
            h3: "Şöyle de: My home is big.",
          },
        },
      ],
    }),
    kit,
    served,
  );
  assertEquals(output.corrections[0].ladder, {
    h1: "Bir kelime eksik.",
    h2: "",
    h3: "",
  });
  assertEquals(leaked, ["0.h2", "0.h3"]);
});
