import { strict as assert } from "node:assert";
import test from "node:test";
import { handle } from "../handler.js";
import { resetRateLimits } from "../rateLimit.js";
import { AnalysisRequestSchema, SCHEMA_VERSION } from "../schema.js";

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
});

test("the request contract accepts what the app actually sends", () => {
  const parsed = AnalysisRequestSchema.safeParse(JSON.parse(validBody()));
  assert.ok(parsed.success);
});

test("an old schema version is refused rather than misread", () => {
  const parsed = AnalysisRequestSchema.safeParse(JSON.parse(validBody({ schemaVersion: 0 })));
  assert.equal(parsed.success, false);
});
