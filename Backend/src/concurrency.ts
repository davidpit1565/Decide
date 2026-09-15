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
 */
let active = 0;

export function tryAcquire(limit: number): boolean {
  if (active >= limit) return false;
  active += 1;
  return true;
}

export function release(): void {
  active = Math.max(0, active - 1);
}

export function currentlyActive(): number {
  return active;
}

export function resetConcurrency(): void {
  active = 0;
}
