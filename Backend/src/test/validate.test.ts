import { strict as assert } from "node:assert";
import test from "node:test";
import { toWireResponse, stripConfidenceClaims } from "../validate.js";
import { budgetFor } from "../budget.js";
import { AnalysisRequestSchema, DecisionResponseSchema, SCHEMA_VERSION } from "../schema.js";
import type { AnalysisRequest, DecisionResponse } from "../schema.js";

function makeRequest(overrides: Record<string, unknown> = {}): AnalysisRequest {
  return AnalysisRequestSchema.parse({
    schemaVersion: SCHEMA_VERSION,
    prompt: "MacBook Air or MacBook Pro?",
    category: "technology",
    complexity: "medium",
    researchLevel: "light",
    maximumResearchCalls: 2,
    maximumSources: 4,
    questionsAlreadyAsked: 0,
    questionCeiling: 3,
    ...overrides,
  });
}

function makeResponse(overrides: Partial<DecisionResponse> = {}): DecisionResponse {
  return DecisionResponseSchema.parse({
    decisionStatus: "ready",
    category: "technology",
    complexity: "medium",
    understanding: { restatement: "You're choosing a laptop.", knownContext: [], whatMatters: [] },
    preliminaryRecommendation: null,
    requiredQuestions: [],
    researchNeeded: { level: "light", topics: [] },
    criteria: [{ id: "portability", name: "Portability", weight: 0.6, rationale: null }],
    options: [
      {
        id: "air",
        name: "MacBook Air",
        summary: null,
        scores: [{ criterionId: "portability", score: 0.9 }],
        failedConstraints: [],
      },
    ],
    recommendation: { optionId: "air", headline: "Best fit", reasons: [] },
    tradeoffs: [],
    risks: [],
    assumptions: [],
    research: [],
    conflicts: [],
    whatCouldMakeMeWrong: [],
    ...overrides,
  });
}

test("scores become the map shape the app decodes", () => {
  const request = makeRequest();
  const wire = toWireResponse(makeResponse(), request, budgetFor(request), new Map());
  assert.deepEqual(wire.options[0]!.scores, { portability: 0.9 });
  assert.equal(wire.schemaVersion, SCHEMA_VERSION);
});

test("a score for a criterion that does not exist is dropped", () => {
  const request = makeRequest();
  const response = makeResponse({
    options: [
      {
        id: "air",
        name: "MacBook Air",
        summary: null,
        scores: [
          { criterionId: "portability", score: 0.9 },
          { criterionId: "ghost", score: 0.2 },
        ],
        failedConstraints: [],
      },
    ],
  });
  const wire = toWireResponse(response, request, budgetFor(request), new Map());
  assert.deepEqual(Object.keys(wire.options[0]!.scores), ["portability"]);
});

test("a recommendation for an option that does not exist is removed", () => {
  const request = makeRequest();
  const response = makeResponse({
    recommendation: { optionId: "ghost", headline: "Ghost", reasons: [] },
  });
  const wire = toWireResponse(response, request, budgetFor(request), new Map());
  assert.equal(wire.recommendation, null);
});

test("a citation that was not retrieved is stripped and marked unverified", () => {
  const request = makeRequest();
  const response = makeResponse({
    research: [
      {
        claim: "The Air weighs 1.24 kg.",
        sourceTitle: "Apple",
        sourceUrl: "https://apple.com/invented",
        retrievedAt: "2026-09-01T00:00:00Z",
        verified: true,
      },
    ],
  });
  const wire = toWireResponse(response, request, budgetFor(request), new Map());
  assert.equal(wire.research[0]!.sourceUrl, null);
  assert.equal(wire.research[0]!.verified, false);
});

test("a citation that was actually retrieved survives, with the real title", () => {
  const request = makeRequest();
  const retrieved = new Map([["https://apple.com/specs", "Apple technical specifications"]]);
  const response = makeResponse({
    research: [
      {
        claim: "The Air weighs 1.24 kg.",
        sourceTitle: "Some other title",
        sourceUrl: "https://apple.com/specs",
        retrievedAt: "2026-09-01T00:00:00Z",
        verified: true,
      },
    ],
  });
  const wire = toWireResponse(response, request, budgetFor(request), retrieved);
  assert.equal(wire.research[0]!.sourceUrl, "https://apple.com/specs");
  assert.equal(wire.research[0]!.sourceTitle, "Apple technical specifications");
  assert.equal(wire.research[0]!.verified, true);
});

test("questions the system could research itself never reach the app", () => {
  const request = makeRequest();
  const response = makeResponse({
    requiredQuestions: [
      {
        id: "price",
        text: "What does it cost today?",
        kind: "free_text",
        choices: [],
        expectedImpact: 0.8,
        friction: 0.4,
        answerableByResearch: true,
        knowledgeKey: null,
      },
      {
        id: "budget",
        text: "What's your budget?",
        kind: "free_text",
        choices: [],
        expectedImpact: 0.9,
        friction: 0.2,
        answerableByResearch: false,
        knowledgeKey: null,
      },
    ],
  });
  const wire = toWireResponse(response, request, budgetFor(request), new Map());
  assert.equal(wire.requiredQuestions.length, 1);
  assert.equal(wire.requiredQuestions[0]!.id, "budget");
});

test("questions beyond the remaining budget are cut", () => {
  const request = makeRequest({ questionCeiling: 1, questionsAlreadyAsked: 1 });
  const response = makeResponse({
    requiredQuestions: [
      {
        id: "a", text: "A?", kind: "free_text", choices: [],
        expectedImpact: 0.9, friction: 0.1, answerableByResearch: false, knowledgeKey: null,
      },
    ],
  });
  const wire = toWireResponse(response, request, budgetFor(request), new Map());
  assert.equal(wire.requiredQuestions.length, 0);
});

test("the model cannot ask for a bigger research budget than it was given", () => {
  const request = makeRequest({ researchLevel: "none", maximumResearchCalls: 0 });
  const response = makeResponse({ researchNeeded: { level: "deep", topics: ["everything"] } });
  const wire = toWireResponse(response, request, budgetFor(request), new Map());
  assert.equal(wire.researchNeeded.level, "none");
});

test("fabricated confidence numbers are stripped from user-facing text", () => {
  assert.equal(
    stripConfidenceClaims("I am 92% confident this is right."),
    "I am confident this is right."
  );
  assert.equal(
    stripConfidenceClaims("87% sure the Air is better"),
    "confident the Air is better"
  );
  assert.equal(
    stripConfidenceClaims("with confidence of 0.95"),
    "with confidence"
  );
  assert.equal(
    stripConfidenceClaims("The Air is lighter by 30%."),
    "The Air is lighter by 30%.",
    "an ordinary percentage is left alone"
  );
});

test("out of range and non-finite scores are clamped, never propagated", () => {
  const request = makeRequest();
  const response = makeResponse();
  // Bypass the schema the way a malformed-but-parseable payload would.
  (response.options[0]!.scores as Array<{ criterionId: string; score: number }>)[0]!.score = 5;
  const wire = toWireResponse(response, request, budgetFor(request), new Map());
  assert.equal(wire.options[0]!.scores.portability, 1);
});
