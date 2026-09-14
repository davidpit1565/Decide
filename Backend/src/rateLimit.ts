/**
 * A fixed-window limiter, per client.
 *
 * In-process, so it holds for a single instance. Behind more than one instance,
 * back it with a shared store — the interface is deliberately small enough to
 * swap.
 */
export interface RateLimitDecision {
  allowed: boolean;
  retryAfterSeconds: number;
}

interface Window {
  count: number;
  resetsAt: number;
}

const windows = new Map<string, Window>();

export function checkRateLimit(clientKey: string, now: number = Date.now()): RateLimitDecision {
  const limit = Number(process.env.DECIDE_RATE_LIMIT ?? 20);
  const windowMs = Number(process.env.DECIDE_RATE_WINDOW_SECONDS ?? 60) * 1000;

  const existing = windows.get(clientKey);
  if (!existing || existing.resetsAt <= now) {
    windows.set(clientKey, { count: 1, resetsAt: now + windowMs });
    pruneExpired(now);
    return { allowed: true, retryAfterSeconds: 0 };
  }

  if (existing.count >= limit) {
    return { allowed: false, retryAfterSeconds: Math.ceil((existing.resetsAt - now) / 1000) };
  }

  existing.count += 1;
  return { allowed: true, retryAfterSeconds: 0 };
}

/** Keeps the map from growing without bound on a long-lived instance. */
function pruneExpired(now: number): void {
  if (windows.size < 10_000) return;
  for (const [key, window] of windows) {
    if (window.resetsAt <= now) windows.delete(key);
  }
}

export function resetRateLimits(): void {
  windows.clear();
}
