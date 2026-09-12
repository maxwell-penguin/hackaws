import Anthropic from "@anthropic-ai/sdk";
import { stripJsonFences } from "../../../lib/strict-json";
import { strapiHeaders } from "../../../lib/strapi";

const anthropic = new Anthropic();

const PROMPT = `You are looking at a photo of a single food item.

Return STRICT JSON only — no markdown, no code fences, no commentary. The output must be a JSON object with exactly these fields:
- name: string, the item name
- description: string, a short one-sentence description of the item
- category: string (e.g. "produce", "dairy", "meat", "pantry", "frozen", "beverage")
- estimatedExpiryDays: integer, typical days until this item expires from today if stored normally`;

const ALLOWED_MEDIA_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/gif",
  "image/webp",
]);

function addDays(days: number): string {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

type ScanResult = {
  name: string;
  description: string;
  category: string;
  estimatedExpiryDays: number;
};

function isValidScanResult(value: unknown): value is ScanResult {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  return (
    typeof v.name === "string" &&
    typeof v.description === "string" &&
    typeof v.category === "string" &&
    typeof v.estimatedExpiryDays === "number" &&
    Number.isFinite(v.estimatedExpiryDays)
  );
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

  // Upload the photo before spending on the vision call, so an upload failure fails fast.
  const uploadForm = new FormData();
  uploadForm.append("files", image);
  const uploadResponse = await fetch(`${strapiUrl}/api/upload`, {
    method: "POST",
    headers: process.env.STRAPI_API_TOKEN
      ? { Authorization: `Bearer ${process.env.STRAPI_API_TOKEN}` }
      : undefined,
    body: uploadForm,
  });
  if (!uploadResponse.ok) {
    const body = await uploadResponse.text();
    return Response.json(
      { error: `Failed to upload photo to Strapi (${uploadResponse.status}): ${body}` },
      { status: 502 },
    );
  }
  const [uploadedFile] = (await uploadResponse.json()) as Array<{ url: string }>;
  const photoUrl = uploadedFile.url.startsWith("/")
    ? `${strapiUrl}${uploadedFile.url}`
    : uploadedFile.url;

  const mediaType = ALLOWED_MEDIA_TYPES.has(image.type) ? image.type : "image/jpeg";
  const imageData = Buffer.from(await image.arrayBuffer()).toString("base64");

  const response = await anthropic.messages.create({
    model: "claude-sonnet-4-6",
    max_tokens: 1024,
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

  let scanResult: ScanResult;
  try {
    const parsed = JSON.parse(stripJsonFences(textBlock.text));
    if (!isValidScanResult(parsed)) throw new Error("invalid shape");
    scanResult = parsed;
  } catch {
    return Response.json(
      { error: "Model did not return valid JSON", raw: textBlock.text },
      { status: 502 },
    );
  }

  const strapiResponse = await fetch(`${strapiUrl}/api/items`, {
    method: "POST",
    headers: strapiHeaders(),
    body: JSON.stringify({
      data: {
        name: scanResult.name,
        description: scanResult.description,
        category: scanResult.category,
        expiryDate: addDays(scanResult.estimatedExpiryDays),
        photoUrl,
        source: "manual-scan",
        status: "active",
        quantity: 1,
        pricePaid: 0,
      },
    }),
  });
  if (!strapiResponse.ok) {
    const body = await strapiResponse.text();
    return Response.json(
      { error: `Strapi create failed (${strapiResponse.status}): ${body}` },
      { status: 502 },
    );
  }

  const { data } = await strapiResponse.json();
  return Response.json({ item: data });
}
