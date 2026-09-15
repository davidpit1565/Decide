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
 * Both are in-process, so they hold for a single instance. Behind more than
 * one instance, back them with a shared store — the interface is deliberately
 * small enough to swap.
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

export function checkRateLimit(clientKey: string, now: number = Date.now()): RateLimitDecision {
  const limit = Number(process.env.DECIDE_RATE_LIMIT ?? 20);
  const windowMs = Number(process.env.DECIDE_RATE_WINDOW_SECONDS ?? 60) * 1000;
  return checkWindow(burstWindows, clientKey, limit, windowMs, now);
}

export function checkDailyLimit(clientKey: string, now: number = Date.now()): RateLimitDecision {
  const limit = Number(process.env.DECIDE_DAILY_LIMIT ?? 200);
  const windowMs = 24 * 60 * 60 * 1000;
  return checkWindow(dailyWindows, clientKey, limit, windowMs, now);
}

function checkWindow(
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
