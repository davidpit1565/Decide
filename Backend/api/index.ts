import type { IncomingMessage, ServerResponse } from "node:http";
import { handle } from "../src/handler.js";
import { resolveClientKey } from "../src/rateLimit.js";

/**
 * Vercel's zero-config Node.js runtime for a bare /api file uses the
 * Node-style (request, response) signature, not the Web Fetch API --
 * `request.headers` here is a plain object, not a Headers instance, and
 * the body is a raw stream. This only translates that shape into
 * handle()'s {method, path, headers, body, clientKey}, which the
 * standalone server in src/index.ts also uses. Same handler, same rules,
 * two hosts.
 *
 * There is no raw socket here -- Vercel Functions are only ever reached
 * through Vercel's own edge network, so there is no separate origin address
 * for x-forwarded-for to be spoofed against. DECIDE_TRUST_PROXY=1 is the
 * correct setting for this deployment target specifically, not a shortcut.
 */
export default async function vercelHandler(
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  const headers: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(request.headers)) {
    headers[key.toLowerCase()] = Array.isArray(value) ? value.join(", ") : value;
  }

  const trustsProxy = process.env.DECIDE_TRUST_PROXY === "1";
  const clientKey = resolveClientKey(headers, undefined, trustsProxy);
  const path = new URL(request.url ?? "/", "http://localhost").pathname;
  const method = request.method ?? "GET";
  const body = method === "GET" || method === "HEAD" ? "" : await readBody(request);

  const result = await handle({ method, path, headers, body, clientKey });

  response.statusCode = result.status;
  for (const [key, value] of Object.entries(result.headers)) {
    response.setHeader(key, value);
  }
  response.end(result.body);
}

function readBody(request: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    request.on("data", (chunk: Buffer) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}
