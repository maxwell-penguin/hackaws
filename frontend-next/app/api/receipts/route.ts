import Anthropic from "@anthropic-ai/sdk";

const anthropic = new Anthropic();

const PROMPT = `You are extracting purchased items from a photo of a grocery receipt or a photo of groceries.

Return STRICT JSON only — no markdown, no code fences, no commentary. The output must be a JSON array where each element has exactly these fields:
- name: string, the item name
- quantity: number
- unit: string (e.g. "count", "lb", "oz", "gallon")
- category: string (e.g. "produce", "dairy", "meat", "pantry", "frozen", "beverage")
- estimatedExpiryDays: integer, typical days until this item expires from today if stored normally

If you cannot identify any items, return an empty array [].`;

const ALLOWED_MEDIA_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/gif",
  "image/webp",
]);

function stripJsonFences(text: string): string {
  const trimmed = text.trim();
  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return fenced ? fenced[1].trim() : trimmed;
}

function addDays(days: number): string {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export async function POST(request: Request) {
  const strapiUrl = process.env.STRAPI_URL;
  if (!strapiUrl) {
    return Response.json({ error: "STRAPI_URL is not configured" }, { status: 500 });
  }

  const formData = await request.formData();
  const image = formData.get("image");
  if (!(image instanceof Blob)) {
    return Response.json({ error: "Missing 'image' file in form data" }, { status: 400 });
  }

  const mediaType = ALLOWED_MEDIA_TYPES.has(image.type) ? image.type : "image/jpeg";
  const imageData = Buffer.from(await image.arrayBuffer()).toString("base64");

  const response = await anthropic.messages.create({
    model: "claude-sonnet-4-6",
    max_tokens: 4096,
    messages: [
      {
        role: "user",
        content: [
          {
            type: "image",
            source: { type: "base64", media_type: mediaType as any, data: imageData },
          },
          { type: "text", text: PROMPT },
        ],
      },
    ],
  });

  const textBlock = response.content.find((block) => block.type === "text");
  if (!textBlock) {
    return Response.json({ error: "No text response from model" }, { status: 502 });
  }

  let items: Array<{
    name: string;
    quantity: number;
    unit: string;
    category: string;
    estimatedExpiryDays: number;
  }>;
  try {
    items = JSON.parse(stripJsonFences(textBlock.text));
    if (!Array.isArray(items)) throw new Error("not an array");
  } catch {
    return Response.json(
      { error: "Model did not return valid JSON", raw: textBlock.text },
      { status: 502 },
    );
  }

  const strapiHeaders: Record<string, string> = { "Content-Type": "application/json" };
  if (process.env.STRAPI_API_TOKEN) {
    strapiHeaders.Authorization = `Bearer ${process.env.STRAPI_API_TOKEN}`;
  }

  const created = await Promise.all(
    items.map(async (item) => {
      const strapiResponse = await fetch(`${strapiUrl}/api/items`, {
        method: "POST",
        headers: strapiHeaders,
        body: JSON.stringify({
          data: {
            name: item.name,
            quantity: item.quantity,
            unit: item.unit,
            category: item.category,
            expiryDate: addDays(item.estimatedExpiryDays),
          },
        }),
      });

      if (!strapiResponse.ok) {
        const errorBody = await strapiResponse.text();
        throw new Error(`Strapi create failed (${strapiResponse.status}): ${errorBody}`);
      }

      const { data } = await strapiResponse.json();
      return data;
    }),
  );

  return Response.json({ items: created });
}
