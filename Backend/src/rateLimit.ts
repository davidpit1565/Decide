import { isConfigured, pipeline } from "./redis.js";

/**
 * Two fixed-window limiters, per client: a short burst window, and a much
 * longer one behind it.
 *
 * The burst window alone caps how fast a client can spend, but not how long
 * it can sustain spending at exactly that rate — a client sitting right at
 * the limit for a full day faces no ceiling beyond the model provider's own
 * account-level limits. The daily window closes that: it still allows the
 * same burst behaviour a real user needs, but bounds the worst case from any
 * one identity over a sustained attack.
 *
 * Backed by Redis when configured (see redis.ts) so the count actually holds
 * across requests, wherever they land. Falls back to an in-process Map for
 * local development and tests, where there is only ever one process anyway.
 */
export interface RateLimitDecision {
  allowed: boolean;
  retryAfterSeconds: number;
}

interface Window {
  count: number;
  resetsAt: number;
}

const burstWindows = new Map<string, Window>();
const dailyWindows = new Map<string, Window>();

export async function checkRateLimit(clientKey: string, now: number = Date.now()): Promise<RateLimitDecision> {
  const limit = Number(process.env.DECIDE_RATE_LIMIT ?? 20);
  const windowSeconds = Number(process.env.DECIDE_RATE_WINDOW_SECONDS ?? 60);
  if (isConfigured()) return checkWindowRedis("burst", clientKey, limit, windowSeconds);
  return checkWindowLocal(burstWindows, clientKey, limit, windowSeconds * 1000, now);
}

export async function checkDailyLimit(clientKey: string, now: number = Date.now()): Promise<RateLimitDecision> {
  const limit = Number(process.env.DECIDE_DAILY_LIMIT ?? 200);
  const windowSeconds = 24 * 60 * 60;
  if (isConfigured()) return checkWindowRedis("daily", clientKey, limit, windowSeconds);
  return checkWindowLocal(dailyWindows, clientKey, limit, windowSeconds * 1000, now);
}

/** EXPIRE ... NX only sets a TTL that isn't already there, so concurrent
 * callers racing the first hit of a window can't keep pushing it back. */
async function checkWindowRedis(
  keyPrefix: string,
  clientKey: string,
  limit: number,
  windowSeconds: number
): Promise<RateLimitDecision> {
  const key = `decide:rl:${keyPrefix}:${clientKey}`;
  try {
    const [count, , ttl] = await pipeline([
      ["INCR", key],
      ["EXPIRE", key, windowSeconds, "NX"],
      ["TTL", key],
    ]);
    if (Number(count) <= limit) return { allowed: true, retryAfterSeconds: 0 };
    const seconds = Number(ttl);
    return { allowed: false, retryAfterSeconds: seconds > 0 ? seconds : windowSeconds };
  } catch {
    // Fails closed: a limiter that can't be reached must not become an
    // unlimited one. This is the one deliberate availability cost of closing
    // the cost-exposure gap the in-process counters left open on Vercel.
    return { allowed: false, retryAfterSeconds: 5 };
  }
}

function checkWindowLocal(
  store: Map<string, Window>,
  clientKey: string,
  limit: number,
  windowMs: number,
  now: number
): RateLimitDecision {
  const existing = store.get(clientKey);
  if (!existing || existing.resetsAt <= now) {
    store.set(clientKey, { count: 1, resetsAt: now + windowMs });
    pruneExpired(store, now);
    return { allowed: true, retryAfterSeconds: 0 };
  }

  if (existing.count >= limit) {
    return { allowed: false, retryAfterSeconds: Math.ceil((existing.resetsAt - now) / 1000) };
  }

  existing.count += 1;
  return { allowed: true, retryAfterSeconds: 0 };
}

/** Keeps a map from growing without bound on a long-lived instance. */
function pruneExpired(store: Map<string, Window>, now: number): void {
  if (store.size < 10_000) return;
  for (const [key, window] of store) {
    if (window.resetsAt <= now) store.delete(key);
  }
}

export function resetRateLimits(): void {
  burstWindows.clear();
  dailyWindows.clear();
}

/**
 * Who this request counts against.
 *
 * `x-forwarded-for` is set by the client unless a proxy overwrites it, so
 * trusting it by default would hand anyone a way around the limiter: rotate the
 * header, get a fresh budget. It is honoured only when the deployment declares
 * that it sits behind a proxy which sets it.
 */
export function resolveClientKey(
  headers: Record<string, string | undefined>,
  remoteAddress: string | undefined,
  trustsProxy: boolean = process.env.DECIDE_TRUST_PROXY === "1"
): string {
  if (trustsProxy) {
    const forwarded = headers["x-forwarded-for"]?.split(",")[0]?.trim();
    if (forwarded) return forwarded;
  }
  return remoteAddress || "unknown";
}
