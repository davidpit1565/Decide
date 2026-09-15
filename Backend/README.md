# DECIDE backend

One endpoint. It exists so the iPhone app never has to hold a model provider
credential, and so the cost of a decision can be controlled somewhere the user
cannot tamper with.

```
iPhone  ->  POST /v1/decisions/analyze  ->  Anthropic API  ->  validated JSON  ->  iPhone
```

## What it does

1. **Validates the request** against the shared contract (`src/schema.ts`) before
   anything is spent.
2. **Rate limits** per client — a short burst window and a much longer daily
   one — and optionally requires a bearer token.
3. **Caps concurrency** globally, so however many identities arrive at once,
   only a bounded number can be spending money at the same time.
4. **Sets a budget** from the decision's complexity (`src/budget.ts`): effort
   level, token ceiling, and how many web searches the decision is worth. A
   trivial decision buys no research at all.
5. **Researches** what can be researched (`src/research.ts`), recording every URL
   the search tool actually returned.
6. **Analyses** with a required output schema (`src/analyze.ts`), so the response
   is structured rather than parsed out of prose.
7. **Validates again** (`src/validate.ts`) — this is the part that matters:
   - a citation whose URL was not actually retrieved is stripped and marked
     unverified, so a fabricated source cannot reach the user;
   - a recommendation pointing at an option that does not exist is removed;
   - questions beyond the app's budget, or that the system could research itself,
     are dropped;
   - the model cannot talk its way into a bigger research budget;
   - any confidence percentage in user-facing text is removed. Decision strength
     is computed on the device by re-running the analysis under varied
     priorities — a number from the model would be invented certainty.

## Running it

```bash
cp .env.example .env     # add your ANTHROPIC_API_KEY
npm install
npm test                 # 43 tests, no network, no spend
npm run build && npm start
```

The app expects `DecideAPIBaseURL` (in `Config/Shared.xcconfig`) to point at this
service over HTTPS. Anything that is not https is ignored by the app.

## Deploying

The handler in `src/handler.ts` is framework-agnostic — `{method, path, headers,
body, clientKey}` in, `{status, headers, body}` out — so it drops into a
serverless function or sits behind the standalone server in `src/index.ts`.
Whatever runs it must terminate TLS.

Set in the environment, never in code:

| Variable | Purpose |
|---|---|
| `ANTHROPIC_API_KEY` | The only credential. Never leaves the server. |
| `DECIDE_RATE_LIMIT`, `DECIDE_RATE_WINDOW_SECONDS` | Requests per burst window, per client. |
| `DECIDE_DAILY_LIMIT` | Requests per 24h, per client — bounds sustained abuse the burst window alone does not. |
| `DECIDE_MAX_CONCURRENT_ANALYSES` | How many analyses may run at once, across every client. |
| `DECIDE_TRUST_PROXY` | `1` only if a proxy you control sets `x-forwarded-for` *and* the origin is not otherwise reachable. Read `.env.example` before setting this — wrong in either direction is a real problem, not a formality. |
| `DECIDE_CLIENT_TOKEN` | Optional bearer token. Coarse filter only — see below. |
| `DECIDE_REQUIRE_ATTESTATION` | `1` refuses every request until App Attest is implemented. |

## Known gap: who is allowed to call this

There is currently no way to verify that a request came from a genuine copy of
the app. `DECIDE_CLIENT_TOKEN` is a shared secret compiled into the app binary —
extractable by anyone who decompiles it — so it raises the cost of casual
discovery without stopping a motivated attacker. The real answer is Apple's
App Attest: the app produces a per-request assertion and the server verifies it
against the registered key. The hook is in `src/attest.ts`, and it is
deliberately binary rather than partial: `DECIDE_REQUIRE_ATTESTATION=1` refuses
*every* request (including real ones — there is no soft-pass), because a check
that pretends to run is worse than an honest gap. It has not been implemented;
turning it on is a kill switch, not a defense, until it is.

Until App Attest exists, if this endpoint's URL becomes known, anyone can call
it, gated only by the burst limit, the daily limit, the global concurrency cap,
and — if set — the bearer token. None of those establish *identity*; they only
bound the damage. Treat that as the actual security boundary this backend
offers today, and size `DECIDE_RATE_LIMIT` / `DECIDE_DAILY_LIMIT` /
`DECIDE_MAX_CONCURRENT_ANALYSES` for the worst case you can tolerate, not the
expected case — see "Cost" below for what one request can cost at the ceiling.

All three limiters (burst, daily, concurrency) are in-process. Deployed behind
more than one instance, each instance enforces its own copy, so the effective
ceiling multiplies by the instance count — either run a single instance until
that matters, or back all three with a shared store.

This also means the backend has no notion of Free vs. Pro: that limit lives
entirely in the app's local state (`FeatureAccess` in
`App/App/AppEnvironment.swift`) and this endpoint enforces no purchase of its
own. Calling it directly, bypassing the app, gets the same access a paying
user gets — one more reason the limits above should reflect the worst case,
not the expected one.

## Cost

Effort is the cost lever, not a cheaper model: one model means one prompt cache
and one set of API semantics, and low effort on the current model buys more
quality per unit of spend than a downgrade. The map lives in `src/budget.ts`:

| Complexity | Effort | Searches | Max tokens |
|---|---|---|---|
| simple | low | 0 | 8,000 |
| medium | medium | up to 2 | 8,000 |
| complex | high | up to 6 | 16,000 |

The system prompt is cached, so the per-request cost is dominated by the decision
itself rather than by the instructions.

## The contract

`src/schema.ts` mirrors `AIDecisionResponse` in
`Packages/DecideKit/Sources/DecideCore/AI/AIContract.swift`. They are kept honest
by a test on each side: the backend's contract test writes a real response to
`Packages/DecideKit/Tests/DecideCoreTests/Fixtures/backend_contract.json`, and
the Swift suite decodes and validates that same file. Break either side and both
suites fail.
