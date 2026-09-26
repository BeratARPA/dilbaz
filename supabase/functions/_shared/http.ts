/** JSON responses with CORS headers for the web client (docs/12 §10). */

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Error payload: a stable code only, never a message with user data. */
export function jsonError(status: number, code: string): Response {
  return json({ error: { code } }, status);
}

export function preflight(): Response {
  return new Response(null, { status: 204, headers: corsHeaders });
}
