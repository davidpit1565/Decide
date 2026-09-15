import { strict as assert } from "node:assert";
import test from "node:test";
import { checkRateLimit, checkDailyLimit } from "../rateLimit.js";

function setFakeRedis(): void {
  process.env.DECIDE_KV_KV_REST_API_URL = "https://fake.upstash.io";
  process.env.DECIDE_KV_KV_REST_API_TOKEN = "test-token";
}

function clearFakeRedis(): void {
  delete process.env.DECIDE_KV_KV_REST_API_URL;
  delete process.env.DECIDE_KV_KV_REST_API_TOKEN;
}

function stubPipelineResult(results: unknown[]): void {
  globalThis.fetch = (async () =>
    new Response(JSON.stringify(results.map((result) => ({ result }))), { status: 200 })) as typeof fetch;
}

test("under the limit, Redis-backed checkRateLimit allows the request", async () => {
  setFakeRedis();
  const originalFetch = globalThis.fetch;
  process.env.DECIDE_RATE_LIMIT = "20";
  stubPipelineResult([5, null, 45]);

  try {
    const decision = await checkRateLimit("client-a");
    assert.equal(decision.allowed, true);
    assert.equal(decision.retryAfterSeconds, 0);
  } finally {
    globalThis.fetch = originalFetch;
    delete process.env.DECIDE_RATE_LIMIT;
    clearFakeRedis();
  }
});

test("over the limit, Redis-backed checkDailyLimit blocks and reports the TTL", async () => {
  setFakeRedis();
  const originalFetch = globalThis.fetch;
  process.env.DECIDE_DAILY_LIMIT = "200";
  stubPipelineResult([201, null, 3600]);

  try {
    const decision = await checkDailyLimit("client-b");
    assert.equal(decision.allowed, false);
    assert.equal(decision.retryAfterSeconds, 3600);
  } finally {
    globalThis.fetch = originalFetch;
    delete process.env.DECIDE_DAILY_LIMIT;
    clearFakeRedis();
  }
});

test("an unreachable Redis fails closed rather than allowing unlimited requests", async () => {
  setFakeRedis();
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async () => {
    throw new Error("network down");
  }) as typeof fetch;

  try {
    const decision = await checkRateLimit("client-c");
    assert.equal(decision.allowed, false, "a limiter that can't be reached must not become an unlimited one");
    assert.ok(decision.retryAfterSeconds > 0);
  } finally {
    globalThis.fetch = originalFetch;
    clearFakeRedis();
  }
});
