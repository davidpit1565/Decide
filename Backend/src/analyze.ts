import Anthropic, { APIConnectionError, APIError, RateLimitError } from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { DecisionResponseSchema, type AnalysisRequest, type WireResponse } from "./schema.js";
import { budgetFor } from "./budget.js";
import { SYSTEM_PROMPT, buildUserMessage } from "./prompt.js";
import { renderResearchNotes, runResearch } from "./research.js";
import { toWireResponse } from "./validate.js";

export class AnalysisError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = "AnalysisError";
  }
}

/**
 * The whole pipeline for one decision: research what can be researched, then
 * analyse, then validate before anything is returned.
 */
export async function analyse(client: Anthropic, request: AnalysisRequest): Promise<WireResponse> {
  const budget = budgetFor(request);

  let researchNotes: string | null = null;
  let retrievedUrls = new Map<string, string>();

  try {
    const research = await runResearch(client, request, budget);
    if (research) {
      researchNotes = renderResearchNotes(research);
      retrievedUrls = research.retrievedUrls;
    }
  } catch {
    // Research is best-effort: the analysis proceeds and says what it could not
    // verify, rather than failing the whole decision.
    researchNotes = null;
  }

  let response;
  try {
    response = await client.messages.parse({
      model: budget.model,
      max_tokens: budget.maxTokens,
      system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
      output_config: {
        effort: budget.effort,
        format: zodOutputFormat(DecisionResponseSchema),
      },
      messages: [{ role: "user", content: buildUserMessage(request, budget, researchNotes) }],
    });
  } catch (error) {
    // Server-side only, never sent to the client: just enough to diagnose an
    // upstream failure (type, HTTP status, Anthropic's own message) without
    // logging the request, the response, or anything from process.env.
    if (error instanceof APIError) {
      console.error("Anthropic API error", { name: error.constructor.name, status: error.status, message: error.message });
    } else {
      console.error("analyse() failed before an API response", error instanceof Error ? error.message : error);
    }

    if (error instanceof RateLimitError) {
      throw new AnalysisError("rate_limited_upstream", 429);
    }
    if (error instanceof APIConnectionError) {
      throw new AnalysisError("upstream_unavailable", 503);
    }
    if (error instanceof APIError) {
      throw new AnalysisError("upstream_error", 502);
    }
    throw new AnalysisError("analysis_failed", 502);
  }

  if (response.stop_reason === "refusal") {
    throw new AnalysisError("refused", 422);
  }

  // Re-validated here rather than trusted: the parse helper and this server
  // must agree before anything reaches the app.
  const parsed = DecisionResponseSchema.safeParse(response.parsed_output);
  if (!parsed.success) {
    throw new AnalysisError("unparseable_response", 502);
  }

  return toWireResponse(parsed.data, request, budget, retrievedUrls);
}
