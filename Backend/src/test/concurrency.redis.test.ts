import { strict as assert } from "node:assert";
import test from "node:test";
import { tryAcquire, release } from "../concurrency.js";

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

test("Redis-backed tryAcquire allows a slot within the limit", async () => {
  setFakeRedis();
  const originalFetch = globalThis.fetch;
  stubPipelineResult([2, null]);

  try {
    assert.equal(await tryAcquire(5), true);
  } finally {
    globalThis.fetch = originalFetch;
    clearFakeRedis();
  }
});

test("Redis-backed tryAcquire refuses over the limit and gives the slot back", async () => {
  setFakeRedis();
  const originalFetch = globalThis.fetch;
  let decrCalled = false;
  globalThis.fetch = (async (_url: string | URL, init?: RequestInit) => {
    const commands = JSON.parse(String(init?.body)) as string[][];
    if (commands[0]?.[0] === "DECR") {
      decrCalled = true;
      return new Response(JSON.stringify([{ result: 5 }]), { status: 200 });
    }
    return new Response(JSON.stringify([{ result: 6 }, { result: null }]), { status: 200 });
  }) as typeof fetch;

  try {
    assert.equal(await tryAcquire(5), false, "the sixth caller is over the limit");
    assert.equal(decrCalled, true, "the over-limit increment is undone");
  } finally {
    globalThis.fetch = originalFetch;
    clearFakeRedis();
  }
});

test("an unreachable Redis fails closed rather than allowing unlimited concurrency", async () => {
  setFakeRedis();
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async () => {
    throw new Error("network down");
  }) as typeof fetch;

  try {
    assert.equal(await tryAcquire(5), false);
    await release(); // best-effort; must not throw even though Redis is down
  } finally {
    globalThis.fetch = originalFetch;
    clearFakeRedis();
  }
});
