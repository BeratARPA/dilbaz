import { adminClient } from "../_shared/admin.ts";
import { verifyUser } from "../_shared/auth.ts";
import { geminiModel } from "../_shared/llm/gemini.ts";
import { groqModel } from "../_shared/llm/groq.ts";
import { llmConfig } from "../_shared/llm_config.ts";
import type { LlmModel } from "../_shared/llm/types.ts";
import { createTutorHandler } from "./handler.ts";

const admin = adminClient();

/** Every configured model whose provider has a key. */
const models = new Map<string, LlmModel>();
const geminiKey = Deno.env.get(llmConfig.providers.gemini.keyEnv);
const groqKey = Deno.env.get(llmConfig.providers.groq.keyEnv);
for (const [id, model] of Object.entries(llmConfig.models)) {
  if (model.provider === "gemini" && geminiKey) {
    models.set(id, geminiModel(id, geminiKey));
  }
  if (model.provider === "groq" && groqKey) {
    models.set(id, groqModel(id, groqKey));
  }
}

Deno.serve(createTutorHandler({
  verifyUser,
  llm: {
    models,
    async learnerState(userId, asked) {
      const [profile, counts] = await Promise.all([
        admin.from("profiles").select("settings").eq("id", userId)
          .maybeSingle(),
        admin.rpc("llm_usage_counts", {
          p_profile_id: userId,
          p_models: asked.map((model) => model.id),
          p_since: asked.map((model) => model.since.toISOString()),
        }),
      ]);
      if (profile.error) throw new Error(profile.error.code);
      if (counts.error) throw new Error(counts.error.code);
      const rows = (counts.data ?? []) as {
        model: string;
        requests: number;
        tokens: number;
      }[];
      return {
        consent: profile.data?.settings?.ai_data_consent?.granted === true,
        use: new Map(rows.map((row) => [row.model, {
          requests: Number(row.requests),
          tokens: Number(row.tokens),
        }])),
      };
    },
    async recordUsage(userId, route, calls) {
      const { error } = await admin.from("llm_usage").insert(
        calls.map((call) => ({
          profile_id: userId,
          route,
          provider: call.provider,
          model: call.model,
          input_tokens: call.inputTokens,
          output_tokens: call.outputTokens,
          cache_read_tokens: call.cachedTokens,
          cost_usd: 0,
          stop_reason: call.stopReason,
          latency_ms: call.latencyMs,
        })),
      );
      if (error) throw new Error(error.code);
    },
  },
}));
