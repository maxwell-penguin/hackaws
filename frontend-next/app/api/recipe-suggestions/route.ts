import Anthropic from "@anthropic-ai/sdk";
import { stripJsonFences } from "../../lib/strict-json";

const anthropic = new Anthropic();

type Recipe = {
  name: string;
  usesExpiring: string[];
  missingIngredients: string[];
};

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((v) => typeof v === "string");
}

function isValidRecipesShape(value: unknown): value is { recipes: Recipe[] } {
  if (!value || typeof value !== "object" || !("recipes" in value)) return false;
  const recipes = (value as { recipes: unknown }).recipes;
  if (!Array.isArray(recipes)) return false;
  return recipes.every(
    (r) =>
      r &&
      typeof r === "object" &&
      typeof (r as Recipe).name === "string" &&
      isStringArray((r as Recipe).usesExpiring) &&
      isStringArray((r as Recipe).missingIngredients),
  );
}

function buildPrompt(expiringItems: string[], activeInventory: string[]): string {
  return `You are a kitchen assistant helping avoid food waste.

Items expiring soon (prioritize using these):
${expiringItems.length ? expiringItems.map((i) => `- ${i}`).join("\n") : "(none)"}

Items already in the kitchen (use these where possible to minimize what needs buying):
${activeInventory.length ? activeInventory.map((i) => `- ${i}`).join("\n") : "(none)"}

Suggest 2-3 quick recipes that prioritize using the expiring items, drawing on the active inventory where possible.

Return STRICT JSON only — no markdown, no code fences, no commentary — in exactly this shape:
{
  "recipes": [
    {
      "name": "string",
      "usesExpiring": ["string", ...],
      "missingIngredients": ["string", ...]
    }
  ]
}

"usesExpiring" must only list items from the expiring-soon list above that this recipe uses. "missingIngredients" lists anything the recipe needs that isn't in the active inventory.`;
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Request body must be JSON" }, { status: 400 });
  }

  const expiringItems = (body as { expiringItems?: unknown })?.expiringItems;
  const activeInventory = (body as { activeInventory?: unknown })?.activeInventory;
  if (!isStringArray(expiringItems) || !isStringArray(activeInventory)) {
    return Response.json(
      { error: "Expected { expiringItems: string[], activeInventory: string[] }" },
      { status: 400 },
    );
  }

  const response = await anthropic.messages.create({
    model: "claude-sonnet-4-6",
    max_tokens: 2048,
    messages: [
      { role: "user", content: buildPrompt(expiringItems, activeInventory) },
    ],
  });

  const textBlock = response.content.find((block) => block.type === "text");
  if (!textBlock) {
    return Response.json({ error: "No text response from model" }, { status: 502 });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(stripJsonFences(textBlock.text));
  } catch {
    return Response.json(
      { error: "Model did not return valid JSON", raw: textBlock.text },
      { status: 502 },
    );
  }

  if (!isValidRecipesShape(parsed)) {
    return Response.json(
      { error: "Model response did not match the expected shape", raw: textBlock.text },
      { status: 502 },
    );
  }

  return Response.json(parsed);
}
