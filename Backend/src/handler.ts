import Anthropic from "@anthropic-ai/sdk";
import { AnalysisRequestSchema } from "./schema.js";
import { analyse, AnalysisError } from "./analyze.js";
import { checkRateLimit } from "./rateLimit.js";
import { verifyClient } from "./attest.js";

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
export async function handle(request: HandlerRequest): Promise<HandlerResponse> {
  if (request.method === "GET" && request.path === "/healthz") {
    return json(200, { status: "ok" });
  }

  if (request.method !== "POST" || request.path !== "/v1/decisions/analyze") {
    return json(404, { error: "not_found" });
  }

  const client = verifyClient(request.headers);
  if (!client.ok) {
    return json(client.status, { error: client.reason ?? "forbidden" });
  }

  const limit = checkRateLimit(request.clientKey);
  if (!limit.allowed) {
    return json(429, { error: "rate_limited" }, { "Retry-After": String(limit.retryAfterSeconds) });
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

  try {
    const result = await analyse(getClient(), parsed.data);
    return json(200, result);
  } catch (error) {
    if (error instanceof AnalysisError) {
      return json(error.status === 422 ? 422 : error.status, { error: error.message });
    }
    return json(500, { error: "internal_error" });
  }
}

function json(status: number, body: unknown, extraHeaders: Record<string, string> = {}): HandlerResponse {
  return {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      ...extraHeaders,
    },
    body: JSON.stringify(body),
  };
}
