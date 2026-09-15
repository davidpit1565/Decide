import { handle } from "../src/handler.js";
import { resolveClientKey } from "../src/rateLimit.js";

/**
 * Vercel's Node.js runtime for this file, routed here for every path by
 * vercel.json's rewrite. The framework-agnostic `handle()` in src/handler.ts
 * is unchanged -- this only translates between the Web-standard
 * Request/Response Vercel functions use and handle()'s {method, path,
 * headers, body, clientKey} shape, which the standalone server in
 * src/index.ts also uses. Same handler, same rules, two hosts.
 *
 * There is no raw socket here -- Vercel Functions are only ever reached
 * through Vercel's own edge network, so there is no separate origin address
 * for x-forwarded-for to be spoofed against. DECIDE_TRUST_PROXY=1 is the
 * correct setting for this deployment target specifically, not a shortcut.
 */
export const config = { runtime: "nodejs" };

export default async function vercelHandler(request: Request): Promise<Response> {
  const headers: Record<string, string | undefined> = {};
  request.headers.forEach((value, key) => {
    headers[key.toLowerCase()] = value;
  });

  const trustsProxy = process.env.DECIDE_TRUST_PROXY === "1";
  const clientKey = resolveClientKey(headers, undefined, trustsProxy);
  const path = new URL(request.url).pathname;
  const body = request.method === "GET" || request.method === "HEAD" ? "" : await request.text();

  const response = await handle({
    method: request.method,
    path,
    headers,
    body,
    clientKey,
  });

  return new Response(response.body, {
    status: response.status,
    headers: response.headers,
  });
}
