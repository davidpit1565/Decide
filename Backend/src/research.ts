import type Anthropic from "@anthropic-ai/sdk";
import type { AnalysisRequest } from "./schema.js";
import type { Budget } from "./budget.js";
import { buildResearchPrompt } from "./prompt.js";
import { SYSTEM_PROMPT } from "./prompt.js";

export interface ResearchResult {
  /** The model's brief, passed into the analysis call. */
  notes: string;
  /** Every URL actually returned by the search tool. Nothing else may be cited. */
  retrievedUrls: Map<string, string>;
  searchesUsed: number;
}

/**
 * Phase one: find what can be found.
 *
 * Runs only when the decision justifies it. The URLs collected here are the
 * allow-list for the analysis phase, so a fabricated citation cannot survive.
 */
export async function runResearch(
  client: Anthropic,
  request: AnalysisRequest,
  budget: Budget
): Promise<ResearchResult | null> {
  if (budget.maxSearches === 0) return null;

  const params = {
    model: budget.model,
    max_tokens: 4000,
    system: SYSTEM_PROMPT,
    output_config: { effort: budget.effort },
    tools: [
      {
        type: "web_search_20260209" as const,
        name: "web_search" as const,
        max_uses: budget.maxSearches,
      },
    ],
    messages: [{ role: "user" as const, content: buildResearchPrompt(request, budget) }],
  };

  const messages: Anthropic.MessageParam[] = [...params.messages];
  const retrievedUrls = new Map<string, string>();
  let notes = "";
  let searchesUsed = 0;

  // A server-tool turn can stop with pause_turn; resume it rather than
  // returning a half-finished brief.
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const response = await client.messages.create({ ...params, messages });

    for (const block of response.content) {
      if (block.type === "text") {
        notes += (notes ? "\n" : "") + block.text;
      } else if (block.type === "web_search_tool_result") {
        searchesUsed += 1;
        const content = block.content;
        // An error comes back as a single object, a success as a list.
        if (Array.isArray(content)) {
          for (const result of content) {
            if (result.type === "web_search_result" && result.url) {
              retrievedUrls.set(result.url, result.title ?? result.url);
            }
          }
        }
      }
    }

    // Resuming a paused turn is documented to continue it, not start a fresh
    // one, so the original max_uses should already bound this loop. This
    // enforces that invariant ourselves rather than trusting it silently: if
    // it ever didn't hold, resuming again could multiply the searches spent
    // on a single decision instead of merely finishing the same budget.
    if (response.stop_reason !== "pause_turn" || searchesUsed >= budget.maxSearches) break;
    messages.push({ role: "assistant", content: response.content });
  }

  return { notes: notes.trim(), retrievedUrls, searchesUsed };
}

/** Renders the brief and its sources for the analysis prompt. */
export function renderResearchNotes(research: ResearchResult): string {
  const sources = [...research.retrievedUrls.entries()]
    .map(([url, title]) => `- ${title} — ${url}`)
    .join("\n");

  return [
    research.notes || "(nothing usable was found)",
    "",
    sources ? `SOURCES RETRIEVED (cite only these URLs):\n${sources}` : "NO SOURCES WERE RETRIEVED. Every sourceUrl must be null and verified must be false.",
  ].join("\n");
}
