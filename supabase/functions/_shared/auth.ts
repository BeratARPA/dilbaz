/**
 * Caller authentication (docs/12-architecture.md §7).
 *
 * The platform's `verify_jwt` check does not understand the new API keys, so
 * functions run with `verify_jwt = false` and verify the user's session JWT
 * here, against the project JWKS.
 */
import { verifyAuth } from "@supabase/server/core";

export type AuthOutcome =
  | { ok: true; userId: string }
  | { ok: false; status: number; code: string };

export type UserVerifier = (request: Request) => Promise<AuthOutcome>;

export const verifyUser: UserVerifier = async (request) => {
  const { data, error } = await verifyAuth(request, { auth: "user" });
  if (error) {
    return { ok: false, status: error.status, code: error.code };
  }
  const userId = data.userClaims?.id;
  if (!userId) {
    return { ok: false, status: 401, code: "MISSING_USER" };
  }
  return { ok: true, userId };
};
