/**
 * The service-role client of a function (docs/12-architecture.md §7): it
 * writes usage rows and reads what RLS keeps from the caller's own client.
 */
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/** The project's secret key: named keys on the platform, one key locally. */
function secretKey(): string {
  const named = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (named) return JSON.parse(named)["default"];
  return Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
}

export function adminClient(): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL") ?? "", secretKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
