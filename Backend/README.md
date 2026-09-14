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
2. **Rate limits** per client, and optionally requires a bearer token.
3. **Sets a budget** from the decision's complexity (`src/budget.ts`): effort
   level, token ceiling, and how many web searches the decision is worth. A
   trivial decision buys no research at all.
4. **Researches** what can be researched (`src/research.ts`), recording every URL
   the search tool actually returned.
5. **Analyses** with a required output schema (`src/analyze.ts`), so the response
   is structured rather than parsed out of prose.
6. **Validates again** (`src/validate.ts`) — this is the part that matters:
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
npm test                 # 29 tests, no network, no spend
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
| `DECIDE_RATE_LIMIT`, `DECIDE_RATE_WINDOW_SECONDS` | Requests per window, per client. |
| `DECIDE_CLIENT_TOKEN` | Optional bearer token. Coarse filter only — see below. |
| `DECIDE_REQUIRE_ATTESTATION` | `1` refuses every request until App Attest is implemented. |

## Known gap: who is allowed to call this

A token compiled into the app can be extracted from the app, so `DECIDE_CLIENT_TOKEN`
raises the cost of abuse without preventing it. The real answer is Apple's
App Attest: the app produces a per-request assertion and the server verifies it
against the registered key. The hook is in `src/attest.ts` and is deliberately
fail-closed — turning it on refuses traffic rather than pretending the check
happened. Until then, the rate limiter is the only thing standing between this
endpoint and someone else's bill.

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
