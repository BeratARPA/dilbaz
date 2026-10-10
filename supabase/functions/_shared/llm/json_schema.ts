/**
 * A zod schema as the JSON Schema both providers accept (docs/07 §3).
 *
 * Gemini's `responseJsonSchema` and Groq's strict mode support different
 * subsets. Only structure is sent: types, properties, required fields,
 * enums and array items, with every object closed. Bounds and formats are
 * left to zod, which checks every answer on the server anyway.
 */
import { z } from "zod";
import type { JsonSchema } from "./types.ts";

const kept = new Set([
  "type",
  "properties",
  "required",
  "additionalProperties",
  "items",
  "enum",
  "description",
]);

function strip(node: unknown): unknown {
  if (Array.isArray(node)) return node.map(strip);
  if (node === null || typeof node !== "object") return node;
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(node)) {
    if (!kept.has(key)) continue;
    // Property names are data, not keywords: keep them all.
    out[key] = key === "properties"
      ? Object.fromEntries(
        Object.entries(value as Record<string, unknown>).map((
          [name, sub],
        ) => [name, strip(sub)]),
      )
      : strip(value);
  }
  return out;
}

export function providerSchema(schema: z.ZodType): JsonSchema {
  return strip(z.toJSONSchema(schema, { target: "draft-07" })) as JsonSchema;
}
