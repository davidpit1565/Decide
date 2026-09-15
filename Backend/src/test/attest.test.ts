import { strict as assert } from "node:assert";
import test from "node:test";
import { verifyClient, hasNoClientVerification } from "../attest.js";

function cleanEnv(): void {
  delete process.env.DECIDE_CLIENT_TOKEN;
  delete process.env.DECIDE_REQUIRE_ATTESTATION;
}

test("with nothing configured, every client is accepted", () => {
  cleanEnv();
  const result = verifyClient({});
  assert.equal(result.ok, true);
});

test("hasNoClientVerification is true exactly when verifyClient accepts everyone", () => {
  cleanEnv();
  assert.equal(hasNoClientVerification(), true);

  process.env.DECIDE_CLIENT_TOKEN = "s3cret";
  assert.equal(hasNoClientVerification(), false);
  cleanEnv();

  process.env.DECIDE_REQUIRE_ATTESTATION = "1";
  assert.equal(hasNoClientVerification(), false);
  cleanEnv();
});

test("required attestation is a kill switch, not a soft pass", () => {
  cleanEnv();
  process.env.DECIDE_REQUIRE_ATTESTATION = "1";
  // No amount of headers should get through -- there is no assertion this
  // will accept, because none is verified yet.
  const result = verifyClient({ "x-decide-attestation": "anything-at-all" });
  assert.equal(result.ok, false);
  assert.equal(result.status, 501);
  cleanEnv();
});
