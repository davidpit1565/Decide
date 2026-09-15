import Anthropic from "@anthropic-ai/sdk";
import { AnalysisRequestSchema } from "./schema.js";
import { analyse as defaultAnalyse, AnalysisError } from "./analyze.js";
import { checkRateLimit, checkDailyLimit } from "./rateLimit.js";
import { verifyClient } from "./attest.js";
import { tryAcquire, release } from "./concurrency.js";
import { isConfigured as isRedisConfigured } from "./redis.js";

export interface HandlerRequest {
  method: string;
  path: string;
  headers: Record<string, string | undefined>;
  body: string;
  clientKey: string;
}

export interface HandlerResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
}

/** Only ever overridden by tests, so they can drive the concurrency gate
 * without a real (or fake-but-slow) model call. */
export interface HandlerDependencies {
  analyse?: typeof defaultAnalyse;
}

let cachedClient: Anthropic | null = null;

function getClient(): Anthropic {
  if (!cachedClient) {
    // The credential lives here and only here. It is read from the environment
    // and never echoed into a response or a log line.
    cachedClient = new Anthropic();
  }
  return cachedClient;
}

/** Framework-agnostic so the same code runs standalone or on a serverless host. */
export async function handle(
  request: HandlerRequest,
  deps: HandlerDependencies = {}
): Promise<HandlerResponse> {
  const analyse = deps.analyse ?? defaultAnalyse;

  if (request.method === "GET" && request.path === "/healthz") {
    // redisConfigured is operational visibility, not a secret: whether the
    // rate/concurrency limits are backed by Redis or the (cross-instance
    // unreliable, on a serverless host) in-process fallback.
    return json(200, { status: "ok", redisConfigured: isRedisConfigured() });
  }

  if (request.method !== "POST" || request.path !== "/v1/decisions/analyze") {
    return json(404, { error: "not_found" });
  }

  const client = verifyClient(request.headers);
  if (!client.ok) {
    return json(client.status, { error: client.reason ?? "forbidden" });
  }

  const limit = await checkRateLimit(request.clientKey);
  if (!limit.allowed) {
    return json(429, { error: "rate_limited" }, { "Retry-After": String(limit.retryAfterSeconds) });
  }

  const daily = await checkDailyLimit(request.clientKey);
  if (!daily.allowed) {
    return json(429, { error: "daily_limit_reached" }, { "Retry-After": String(daily.retryAfterSeconds) });
  }

  if (request.body.length > 32_000) {
    return json(413, { error: "payload_too_large" });
  }

  let payload: unknown;
  try {
    payload = JSON.parse(request.body);
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const parsed = AnalysisRequestSchema.safeParse(payload);
  if (!parsed.success) {
    // The reason is deliberately coarse: an error body is not a schema oracle.
    return json(400, { error: "invalid_request" });
  }

  // A ceiling on how many analyses can be in flight at once, independent of
  // client identity — see concurrency.ts for why identity alone is not enough.
  const maxConcurrent = Number(process.env.DECIDE_MAX_CONCURRENT_ANALYSES ?? 5);
  if (!(await tryAcquire(maxConcurrent))) {
    return json(503, { error: "server_busy" }, { "Retry-After": "2" });
  }

  try {
    const result = await analyse(getClient(), parsed.data);
    return json(200, result);
  } catch (error) {
    if (error instanceof AnalysisError) {
      return json(error.status, { error: error.message });
    }
    return json(500, { error: "internal_error" });
  } finally {
    await release();
  }
}

function json(status: number, body: unknown, extraHeaders: Record<string, string> = {}): HandlerResponse {
  return {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Strict-Transport-Security": "max-age=63072000; includeSubDomains",
      ...extraHeaders,
    },
    body: JSON.stringify(body),
  };
}
