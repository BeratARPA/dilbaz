import { adminClient } from "../_shared/admin.ts";
import { verifyUser } from "../_shared/auth.ts";
import { deepgramStt } from "../_shared/speech/deepgram.ts";
import { groqStt } from "../_shared/speech/groq_stt.ts";
import { speechConfig } from "../_shared/speech_config.ts";
import { createSpeechHandler } from "./handler.ts";

const admin = adminClient();
const deepgramKey = Deno.env.get("DEEPGRAM_API_KEY");
const groqKey = Deno.env.get(speechConfig.sttTurkish.serverFallback.keyEnv);

Deno.serve(createSpeechHandler({
  verifyUser,
  english: deepgramKey ? deepgramStt(deepgramKey) : null,
  turkish: groqKey ? groqStt(groqKey) : null,
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
