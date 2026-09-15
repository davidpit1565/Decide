import { strict as assert } from "node:assert";
import test from "node:test";
import type Anthropic from "@anthropic-ai/sdk";
import { runResearch } from "../research.js";
import { budgetFor } from "../budget.js";
import { AnalysisRequestSchema, SCHEMA_VERSION } from "../schema.js";

function makeRequest(overrides: Record<string, unknown> = {}) {
  return AnalysisRequestSchema.parse({
    schemaVersion: SCHEMA_VERSION,
    prompt: "Something to research",
    category: "other",
    complexity: "medium",
    researchLevel: "light",
    maximumResearchCalls: 2,
    maximumSources: 10,
    questionsAlreadyAsked: 0,
    questionCeiling: 3,
    ...overrides,
  });
}

function searchResultBlock(url: string) {
  return {
    type: "web_search_tool_result" as const,
    tool_use_id: "x",
    content: [{ type: "web_search_result" as const, url, title: url }],
  };
}

function fakeClient(create: () => Promise<{ content: unknown[]; stop_reason: string }>): Anthropic {
  return { messages: { create } } as unknown as Anthropic;
}

test("no searches budgeted means no call to the model at all", async () => {
  const request = makeRequest({ researchLevel: "none", maximumResearchCalls: 0, complexity: "simple" });
  const budget = budgetFor(request);
  let called = false;
  const client = fakeClient(async () => {
    called = true;
    throw new Error("should not be called");
  });

  const result = await runResearch(client, request, budget);
  assert.equal(result, null);
  assert.equal(called, false);
});

test("a normal single-call research turn is unaffected", async () => {
  const request = makeRequest();
  const budget = budgetFor(request);
  let callCount = 0;
  const client = fakeClient(async () => {
    callCount += 1;
    return {
      content: [
        { type: "text", text: "Found the current price." },
        searchResultBlock("https://example.com/a"),
      ],
      stop_reason: "end_turn",
    };
  });

  const result = await runResearch(client, request, budget);
  assert.equal(callCount, 1);
  assert.equal(result?.notes, "Found the current price.");
  assert.equal(result?.retrievedUrls.size, 1);
});

test("the resume loop stops once the decision's search budget is spent, even if the model would keep going", async () => {
  // light + maximumResearchCalls: 2 -> budget.maxSearches is exactly 2.
  const request = makeRequest();
  const budget = budgetFor(request);
  assert.equal(budget.maxSearches, 2);

  let callCount = 0;
  const client = fakeClient(async () => {
    callCount += 1;
    // Always reports one more search and always asks to continue -- exactly
    // what a model trying to keep resuming past its budget would look like.
    return {
      content: [searchResultBlock(`https://example.com/${callCount}`)],
      stop_reason: "pause_turn",
    };
  });

  const result = await runResearch(client, request, budget);

  // Without the defensive check, the outer loop's own hard cap (3 attempts)
  // would still let this run one attempt past the decision's actual budget.
  assert.equal(callCount, 2, "stops once the budget is spent rather than resuming a third time");
  assert.equal(result?.searchesUsed, 2);
  assert.equal(result?.retrievedUrls.size, 2);
});
