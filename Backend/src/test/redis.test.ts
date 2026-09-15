import { strict as assert } from "node:assert";
import test from "node:test";
import { isConfigured, pipeline } from "../redis.js";

function setFakeRedis(): void {
  process.env.DECIDE_KV_KV_REST_API_URL = "https://fake.upstash.io";
  process.env.DECIDE_KV_KV_REST_API_TOKEN = "test-token";
}

function clearFakeRedis(): void {
  delete process.env.DECIDE_KV_KV_REST_API_URL;
  delete process.env.DECIDE_KV_KV_REST_API_TOKEN;
}

test("isConfigured is true only when both the URL and token are set", () => {
  clearFakeRedis();
  assert.equal(isConfigured(), false);

  process.env.DECIDE_KV_KV_REST_API_URL = "https://fake.upstash.io";
  assert.equal(isConfigured(), false, "a token-less URL is not enough");

  setFakeRedis();
  assert.equal(isConfigured(), true);
  clearFakeRedis();
});

test("pipeline posts the commands as JSON and unwraps the results", async () => {
  setFakeRedis();
  const originalFetch = globalThis.fetch;
  let capturedUrl = "";
  let capturedAuth = "";
  let capturedBody = "";
  globalThis.fetch = (async (url: string | URL, init?: RequestInit) => {
    capturedUrl = String(url);
    capturedAuth = String((init?.headers as Record<string, string>).Authorization);
    capturedBody = String(init?.body);
    return new Response(JSON.stringify([{ result: 1 }, { result: null }, { result: 60 }]), { status: 200 });
  }) as typeof fetch;

  try {
    const result = await pipeline([
      ["INCR", "k"],
      ["EXPIRE", "k", 60, "NX"],
      ["TTL", "k"],
    ]);
    assert.deepEqual(result, [1, null, 60]);
    assert.equal(capturedUrl, "https://fake.upstash.io/pipeline");
    assert.equal(capturedAuth, "Bearer test-token");
    assert.deepEqual(JSON.parse(capturedBody), [
      ["INCR", "k"],
      ["EXPIRE", "k", 60, "NX"],
      ["TTL", "k"],
    ]);
  } finally {
    globalThis.fetch = originalFetch;
    clearFakeRedis();
  }
});

test("pipeline rejects on a non-2xx response, without a live Redis to ask", async () => {
  setFakeRedis();
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async () => new Response("nope", { status: 500 })) as typeof fetch;

  try {
    await assert.rejects(() => pipeline([["INCR", "k"]]));
  } finally {
    globalThis.fetch = originalFetch;
    clearFakeRedis();
  }
});

test("pipeline rejects when a command in the batch itself errors", async () => {
  setFakeRedis();
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async () =>
    new Response(JSON.stringify([{ result: null, error: "WRONGTYPE" }]), { status: 200 })) as typeof fetch;

  try {
    await assert.rejects(() => pipeline([["INCR", "k"]]));
  } finally {
    globalThis.fetch = originalFetch;
    clearFakeRedis();
  }
});

test("pipeline refuses to run at all when Redis is not configured", async () => {
  clearFakeRedis();
  await assert.rejects(() => pipeline([["INCR", "k"]]));
});
