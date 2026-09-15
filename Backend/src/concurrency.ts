import { isConfigured, pipeline } from "./redis.js";

/**
 * A hard ceiling on simultaneous, in-flight analyse() calls, independent of
 * client identity.
 *
 * The rate limiter counts requests over time, per client key. It says nothing
 * about how many of those calls are running *at once* — and a client key is
 * only as trustworthy as the identity behind it (an IP, freely rotated; a
 * bearer token, extractable from the app). This is the backstop that holds
 * even if every client key is spoofed: however many identities arrive at
 * once, only a bounded number can be spending money against the model
 * provider at the same time.
 *
 * Backed by Redis when configured (see redis.ts) — an in-process counter
 * cannot hold across requests that land on different serverless instances,
 * which is the normal case on Vercel, not an edge case. Falls back to an
 * in-process counter for local development and tests.
 */
let active = 0;

const CONCURRENCY_KEY = "decide:concurrency";
/** Self-heals a slot leaked by an instance that crashed before releasing —
 * comfortably above the server's own 30s request timeout, not a real budget. */
const STALE_SECONDS = 60;

export async function tryAcquire(limit: number): Promise<boolean> {
  if (!isConfigured()) {
    if (active >= limit) return false;
    active += 1;
    return true;
  }
  try {
    const [count] = await pipeline([
      ["INCR", CONCURRENCY_KEY],
      ["EXPIRE", CONCURRENCY_KEY, STALE_SECONDS, "NX"],
    ]);
    if (Number(count) > limit) {
      await pipeline([["DECR", CONCURRENCY_KEY]]);
      return false;
    }
    return true;
  } catch {
    // Fails closed: an unreachable counter must not become unlimited concurrency.
    return false;
  }
}

export async function release(): Promise<void> {
  if (!isConfigured()) {
    active = Math.max(0, active - 1);
    return;
  }
  try {
    await pipeline([["DECR", CONCURRENCY_KEY]]);
  } catch {
    // Best-effort: a failed release only leaks a slot for STALE_SECONDS.
  }
}

export async function currentlyActive(): Promise<number> {
  if (!isConfigured()) return active;
  try {
    const [count] = await pipeline([["GET", CONCURRENCY_KEY]]);
    return Number(count ?? 0);
  } catch {
    return 0;
  }
}

export function resetConcurrency(): void {
  active = 0;
}
