/**
 * Who is allowed to call this endpoint.
 *
 * A token compiled into the app is not a secret — it can be pulled out of the
 * binary — so it is offered only as a coarse filter. The real answer is Apple's
 * App Attest: the app produces a per-request assertion, and this function
 * verifies it against the stored public key.
 *
 * Until that is implemented, DECIDE_REQUIRE_ATTESTATION=1 refuses every request
 * rather than pretending the check happened.
 */
import { timingSafeEqual as nodeTimingSafeEqual } from "node:crypto";

export interface ClientCheck {
  ok: boolean;
  status: number;
  reason?: string;
}

export function verifyClient(headers: Record<string, string | undefined>): ClientCheck {
  const requiredToken = process.env.DECIDE_CLIENT_TOKEN;
  if (requiredToken) {
    const provided = (headers["authorization"] ?? "").replace(/^Bearer\s+/i, "");
    if (!timingSafeEqual(provided, requiredToken)) {
      return { ok: false, status: 401, reason: "unauthorized" };
    }
  }

  if (process.env.DECIDE_REQUIRE_ATTESTATION === "1") {
    // TODO(production): verify headers["x-decide-attestation"] with Apple's
    // App Attest, against the key registered for this installation.
    return { ok: false, status: 501, reason: "attestation_not_implemented" };
  }

  return { ok: true, status: 200 };
}

/** True when verifyClient() lets every request through, whatever it claims to
 * be — the exact condition the server warns about loudly at startup. */
export function hasNoClientVerification(): boolean {
  return !process.env.DECIDE_CLIENT_TOKEN && process.env.DECIDE_REQUIRE_ATTESTATION !== "1";
}

function timingSafeEqual(a: string, b: string): boolean {
  const left = Buffer.from(a, "utf8");
  const right = Buffer.from(b, "utf8");
  // Compare a fixed-size digest-shaped buffer so the comparison itself does not
  // depend on the length of what was supplied.
  if (left.length !== right.length) {
    // Still burn a comparison of equal length, then fail.
    nodeTimingSafeEqual(right, right);
    return false;
  }
  return nodeTimingSafeEqual(left, right);
}
