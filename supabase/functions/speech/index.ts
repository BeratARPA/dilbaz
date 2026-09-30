import { createClient } from "@supabase/supabase-js";
import { verifyUser } from "../_shared/auth.ts";
import { deepgramStt } from "../_shared/speech/deepgram.ts";
import { createSpeechHandler } from "./handler.ts";

/** The project's secret key: named keys on the platform, one key locally. */
function secretKey(): string {
  const named = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (named) return JSON.parse(named)["default"];
  return Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
}

const admin = createClient(Deno.env.get("SUPABASE_URL") ?? "", secretKey(), {
  auth: { persistSession: false, autoRefreshToken: false },
});
const deepgramKey = Deno.env.get("DEEPGRAM_API_KEY");

Deno.serve(createSpeechHandler({
  verifyUser,
  english: deepgramKey ? deepgramStt(deepgramKey) : null,
  recordUsage: async (usage) => {
    const { error } = await admin.from("speech_usage").insert({
      profile_id: usage.profileId,
      provider: usage.provider,
      kind: usage.kind,
      seconds: usage.seconds,
      cost_usd: usage.costUsd,
    });
    if (error) throw new Error(error.code);
  },
}));
