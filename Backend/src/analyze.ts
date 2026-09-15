import Anthropic, { APIConnectionError, APIError, RateLimitError } from "@anthropic-ai/sdk";
import { DecisionResponseSchema, type AnalysisRequest, type WireResponse } from "./schema.js";
import { budgetFor } from "./budget.js";
import { SYSTEM_PROMPT, OUTPUT_FORMAT_INSTRUCTIONS, buildUserMessage } from "./prompt.js";
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
    response = await client.messages.create({
      model: budget.model,
      max_tokens: budget.maxTokens,
      system: [
        { type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } },
        { type: "text", text: OUTPUT_FORMAT_INSTRUCTIONS, cache_control: { type: "ephemeral" } },
      ],
      output_config: { effort: budget.effort },
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

  let text = "";
  for (const block of response.content) {
    if (block.type === "text") text += block.text;
  }

  let rawOutput: unknown;
  try {
    rawOutput = JSON.parse(extractJsonObject(text));
  } catch {
    throw new AnalysisError("unparseable_response", 502);
  }

  // Re-validated here rather than trusted: nothing about the prompted-JSON
  // approach above guarantees the shape, so this is not redundant -- it is
  // the only real enforcement of the contract before anything reaches the app.
  const parsed = DecisionResponseSchema.safeParse(rawOutput);
  if (!parsed.success) {
    throw new AnalysisError("unparseable_response", 502);
  }

  return toWireResponse(parsed.data, request, budget, retrievedUrls);
}

/** Strips an accidental markdown code fence, in case the model adds one
 * despite being told not to. */
function extractJsonObject(text: string): string {
  const trimmed = text.trim();
  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  return fenced ? fenced[1]! : trimmed;
}
