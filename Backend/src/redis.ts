/**
 * A minimal Upstash Redis REST client — just enough for atomic counters.
 *
 * No SDK dependency: Upstash's REST API is a single POST per pipeline, so a
 * plain fetch call is smaller and easier to audit than a client library.
 * The env var names are what Vercel's Upstash integration actually produced
 * for this project (a "DECIDE_KV" prefix layered over an already-prefixed
 * "KV_REST_API_URL" variable, hence the repeated "KV").
 */
function config(): { url: string; token: string } | null {
  const url = process.env.DECIDE_KV_KV_REST_API_URL;
  const token = process.env.DECIDE_KV_KV_REST_API_TOKEN;
  return url && token ? { url, token } : null;
}

export function isConfigured(): boolean {
  return config() !== null;
}

export async function pipeline(commands: Array<Array<string | number>>): Promise<unknown[]> {
  const redis = config();
  if (!redis) throw new Error("redis_not_configured");

  const response = await fetch(`${redis.url}/pipeline`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${redis.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(commands),
  });
  if (!response.ok) throw new Error(`redis_http_${response.status}`);

  const body = (await response.json()) as Array<{ result: unknown; error?: string }>;
  return body.map((entry) => {
    if (entry.error) throw new Error("redis_command_error");
    return entry.result;
  });
}

/** Vercel sets VERCEL=1 on every deployment. On that platform specifically,
 * an in-process counter cannot hold across requests that land on different
 * execution instances — the normal case, not an edge case, confirmed live —
 * so running there without Redis configured means the limits below are not
 * actually enforced. */
export function hasUnreliableRateLimiting(): boolean {
  return process.env.VERCEL === "1" && !isConfigured();
}
