import { strict as assert } from "node:assert";
import test from "node:test";
import { handle } from "../handler.js";
import { resetRateLimits, resolveClientKey } from "../rateLimit.js";
import { resetConcurrency } from "../concurrency.js";
import { AnalysisRequestSchema, SCHEMA_VERSION } from "../schema.js";
import type { WireResponse } from "../schema.js";

/** A fake analyse() whose completion this test controls, so it can hold a
 * concurrency slot open on purpose instead of racing a real timer. */
function controllableAnalyse() {
  let release!: () => void;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  const analyse = async (): Promise<WireResponse> => {
    await gate;
    return { schemaVersion: SCHEMA_VERSION } as unknown as WireResponse;
  };
  return { analyse, release };
}

function validBody(overrides: Record<string, unknown> = {}) {
  return JSON.stringify({
    schemaVersion: SCHEMA_VERSION,
    prompt: "MacBook Air or MacBook Pro?",
    answers: [],
    knownPreferences: [],
    category: "technology",
    complexity: "medium",
    researchLevel: "light",
    maximumResearchCalls: 2,
    maximumSources: 4,
    questionsAlreadyAsked: 0,
    questionCeiling: 3,
    strictSchema: false,
    locale: "en_GB",
    ...overrides,
  });
}

function request(overrides: Partial<Parameters<typeof handle>[0]> = {}) {
  return {
    method: "POST",
    path: "/v1/decisions/analyze",
    headers: {},
    body: validBody(),
    clientKey: `test-${Math.random()}`,
    ...overrides,
  };
}

test("health check responds without touching the model", async () => {
  const response = await handle(request({ method: "GET", path: "/healthz" }));
  assert.equal(response.status, 200);
  assert.deepEqual(JSON.parse(response.body), { status: "ok" });
});

test("unknown routes are 404, not 500", async () => {
  const response = await handle(request({ method: "GET", path: "/" }));
  assert.equal(response.status, 404);
});

test("malformed JSON is rejected before anything is spent", async () => {
  const response = await handle(request({ body: "{not json" }));
  assert.equal(response.status, 400);
  assert.equal(JSON.parse(response.body).error, "invalid_json");
});

test("a request that does not match the contract is rejected", async () => {
  const response = await handle(request({ body: JSON.stringify({ prompt: "hi" }) }));
  assert.equal(response.status, 400);
  assert.equal(JSON.parse(response.body).error, "invalid_request");
});

test("the error body never leaks which field failed", async () => {
  const response = await handle(request({ body: validBody({ category: "nonsense" }) }));
  assert.equal(response.status, 400);
  assert.deepEqual(Object.keys(JSON.parse(response.body)), ["error"]);
});

test("an oversized payload is refused", async () => {
  const response = await handle(request({ body: "x".repeat(40_000) }));
  assert.equal(response.status, 413);
});

test("rate limiting refuses a flood and says when to come back", async () => {
  resetRateLimits();
  process.env.DECIDE_RATE_LIMIT = "3";
  const key = "flood-client";

  for (let index = 0; index < 3; index += 1) {
    const response = await handle(request({ clientKey: key, body: "{bad" }));
    assert.equal(response.status, 400, "within the limit, the request is processed");
  }

  const blocked = await handle(request({ clientKey: key, body: "{bad" }));
  assert.equal(blocked.status, 429);
  assert.ok(Number(blocked.headers["Retry-After"]) > 0);

  delete process.env.DECIDE_RATE_LIMIT;
  resetRateLimits();
});

test("a bearer token is enforced when one is configured", async () => {
  resetRateLimits();
  process.env.DECIDE_CLIENT_TOKEN = "s3cret";

  const rejected = await handle(request({ body: "{bad" }));
  assert.equal(rejected.status, 401);

  const accepted = await handle(
    request({ headers: { authorization: "Bearer s3cret" }, body: "{bad" })
  );
  assert.equal(accepted.status, 400, "past the gate, normal validation applies");

  delete process.env.DECIDE_CLIENT_TOKEN;
});

test("required attestation refuses rather than pretending to check", async () => {
  resetRateLimits();
  process.env.DECIDE_REQUIRE_ATTESTATION = "1";
  const response = await handle(request({ body: "{bad" }));
  assert.equal(response.status, 501);
  delete process.env.DECIDE_REQUIRE_ATTESTATION;
});

test("responses are not cacheable and are typed", async () => {
  const response = await handle(request({ method: "GET", path: "/healthz" }));
  assert.equal(response.headers["Cache-Control"], "no-store");
  assert.equal(response.headers["Content-Type"], "application/json");
  assert.equal(response.headers["X-Content-Type-Options"], "nosniff");
  assert.ok(response.headers["Strict-Transport-Security"]?.includes("max-age"));
});

test("the daily limit trips even while the burst window is nowhere near full", async () => {
  resetRateLimits();
  process.env.DECIDE_RATE_LIMIT = "100";
  process.env.DECIDE_DAILY_LIMIT = "2";
  const key = "sustained-client";

  for (let index = 0; index < 2; index += 1) {
    const response = await handle(request({ clientKey: key, body: "{bad" }));
    assert.equal(response.status, 400, "within the daily limit, the request is processed");
  }

  const blocked = await handle(request({ clientKey: key, body: "{bad" }));
  assert.equal(blocked.status, 429);
  assert.equal(JSON.parse(blocked.body).error, "daily_limit_reached");
  assert.ok(Number(blocked.headers["Retry-After"]) > 0);

  delete process.env.DECIDE_RATE_LIMIT;
  delete process.env.DECIDE_DAILY_LIMIT;
  resetRateLimits();
});

test("a global concurrency cap holds even across many client identities", async () => {
  resetConcurrency();
  process.env.DECIDE_MAX_CONCURRENT_ANALYSES = "2";

  const { analyse, release } = controllableAnalyse();

  // Three different identities: the cap has to hold with no shared client key
  // to hang the block on, or a spoofed identity would buy a spoofed slot.
  const first = handle(request({ clientKey: "a" }), { analyse });
  const second = handle(request({ clientKey: "b" }), { analyse });
  await new Promise((resolve) => setImmediate(resolve));

  const third = await handle(request({ clientKey: "c" }), { analyse });
  assert.equal(third.status, 503, "a third identity does not buy a third concurrent slot");
  assert.equal(JSON.parse(third.body).error, "server_busy");
  assert.ok(Number(third.headers["Retry-After"]) > 0);

  release();
  const [firstResult, secondResult] = await Promise.all([first, second]);
  assert.equal(firstResult.status, 200);
  assert.equal(secondResult.status, 200);

  delete process.env.DECIDE_MAX_CONCURRENT_ANALYSES;
  resetConcurrency();
});

test("a slot is released even when the analysis throws", async () => {
  resetConcurrency();
  process.env.DECIDE_MAX_CONCURRENT_ANALYSES = "1";

  const failing = async (): Promise<WireResponse> => {
    throw new Error("boom");
  };
  const first = await handle(request({ clientKey: "a" }), { analyse: failing });
  assert.equal(first.status, 500);

  // If the slot had leaked, this would come back 503 instead.
  const second = await handle(request({ clientKey: "b" }), { analyse: failing });
  assert.equal(second.status, 500);

  delete process.env.DECIDE_MAX_CONCURRENT_ANALYSES;
  resetConcurrency();
});

test("the request contract accepts what the app actually sends", () => {
  const parsed = AnalysisRequestSchema.safeParse(JSON.parse(validBody()));
  assert.ok(parsed.success);
});

test("an old schema version is refused rather than misread", () => {
  const parsed = AnalysisRequestSchema.safeParse(JSON.parse(validBody({ schemaVersion: 0 })));
  assert.equal(parsed.success, false);
});

test("a forged forwarded-for header cannot buy a fresh rate-limit budget", () => {
  const headers = { "x-forwarded-for": "1.2.3.4" };

  // Exposed directly: the socket address is what counts, so rotating the header
  // changes nothing.
  assert.equal(resolveClientKey(headers, "10.0.0.1", false), "10.0.0.1");
  assert.equal(resolveClientKey({ "x-forwarded-for": "9.9.9.9" }, "10.0.0.1", false), "10.0.0.1");

  // Behind a proxy that sets it, the real client is what counts.
  assert.equal(resolveClientKey(headers, "10.0.0.1", true), "1.2.3.4");
  assert.equal(resolveClientKey({ "x-forwarded-for": "1.2.3.4, 10.0.0.9" }, "10.0.0.1", true), "1.2.3.4");
});

test("a request with no identifiable client still gets a key", () => {
  assert.equal(resolveClientKey({}, undefined, true), "unknown");
});
