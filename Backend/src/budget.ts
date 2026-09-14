import type { AnalysisRequest } from "./schema.js";

/**
 * What one decision is allowed to spend.
 *
 * Effort is the cost lever rather than a cheaper model: a single model keeps one
 * cache namespace and one set of API semantics, and low effort on the current
 * model beats a downgrade on quality per unit of spend. The app has already
 * classified the decision; this only ever narrows what the app asked for.
 */
export const MODEL = "claude-opus-5";

export type Effort = "low" | "medium" | "high";

export interface Budget {
  model: string;
  effort: Effort;
  maxTokens: number;
  /** Server-side web searches allowed for this decision. 0 means no research call at all. */
  maxSearches: number;
  /** Questions the model may return, after what has already been asked. */
  questionsRemaining: number;
}

export function budgetFor(request: AnalysisRequest): Budget {
  const effort: Effort =
    request.complexity === "complex" ? "high"
    : request.complexity === "medium" ? "medium"
    : "low";

  const maxTokens = request.complexity === "complex" ? 16000 : 8000;

  // Research is capped by the app's budget and by complexity, whichever is lower.
  const byLevel = request.researchLevel === "deep" ? 6 : request.researchLevel === "light" ? 2 : 0;
  const maxSearches = Math.max(0, Math.min(byLevel, request.maximumResearchCalls));

  const questionsRemaining = Math.max(
    0,
    Math.min(request.questionCeiling - request.questionsAlreadyAsked, 5)
  );

  return { model: MODEL, effort, maxTokens, maxSearches, questionsRemaining };
}
