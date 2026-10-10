import { assertEquals } from "@std/assert";
import { z } from "zod";
import { providerSchema } from "./json_schema.ts";

Deno.test("only structure goes to the provider; zod keeps the bounds", () => {
  const schema = z.strictObject({
    verdict: z.enum(["correct", "wrong"]),
    confidence: z.number().min(0).max(1),
    tags: z.array(z.string().max(20)).max(3),
    // A property may carry a keyword's name.
    minimum: z.boolean(),
  });

  assertEquals(providerSchema(schema), {
    type: "object",
    properties: {
      verdict: { type: "string", enum: ["correct", "wrong"] },
      confidence: { type: "number" },
      tags: { type: "array", items: { type: "string" } },
      minimum: { type: "boolean" },
    },
    required: ["verdict", "confidence", "tags", "minimum"],
    additionalProperties: false,
  });
});
